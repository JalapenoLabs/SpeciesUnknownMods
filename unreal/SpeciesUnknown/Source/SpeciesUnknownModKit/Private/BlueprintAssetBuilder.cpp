// Copyright © 2026 Jalapeno Labs

#include "BlueprintAssetBuilder.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetTree.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/Image.h"
#include "Components/ProgressBar.h"
#include "Components/TextBlock.h"
#include "EdGraphSchema_K2.h"
#include "EditorAssetLibrary.h"
#include "Engine/Blueprint.h"
#include "GameFramework/Actor.h"
#include "K2Node_CustomEvent.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "ModKitLog.h"
#include "UObject/Package.h"
#include "WidgetBlueprint.h"
#include "Blueprint/WidgetBlueprintGeneratedClass.h"

// Vertical spacing between generated event nodes, so the graph stays readable when opened in the editor.
static constexpr int32 EventNodeSpacing = 200;

// ////////////////////// //
//       Pin types        //
// ////////////////////// //

namespace ModPinTypes {
	FEdGraphPinType Bool() {
		FEdGraphPinType PinType;
		PinType.PinCategory = UEdGraphSchema_K2::PC_Boolean;
		return PinType;
	}

	// Blueprint "Float" variables are doubles since UE 5.0.
	FEdGraphPinType Float() {
		FEdGraphPinType PinType;
		PinType.PinCategory = UEdGraphSchema_K2::PC_Real;
		PinType.PinSubCategory = UEdGraphSchema_K2::PC_Double;
		return PinType;
	}

	FEdGraphPinType Name() {
		FEdGraphPinType PinType;
		PinType.PinCategory = UEdGraphSchema_K2::PC_Name;
		return PinType;
	}

	FEdGraphPinType Vector() {
		FEdGraphPinType PinType;
		PinType.PinCategory = UEdGraphSchema_K2::PC_Struct;
		PinType.PinSubCategoryObject = TBaseStructure<FVector>::Get();
		return PinType;
	}

	FEdGraphPinType Object(UClass* ObjectClass) {
		FEdGraphPinType PinType;
		PinType.PinCategory = UEdGraphSchema_K2::PC_Object;
		PinType.PinSubCategoryObject = ObjectClass;
		return PinType;
	}
}

// ////////////////////// //
//       Entry point      //
// ////////////////////// //

UBlueprint* FBlueprintAssetBuilder::BuildNetworkActor(const FModNetworkActorSpec& Spec) {
	UBlueprint* Blueprint = CreateFreshBlueprint(Spec.AssetPath, AActor::StaticClass(), UBlueprint::StaticClass(),
		UBlueprintGeneratedClass::StaticClass());

	// Creating the asset failed; CreateFreshBlueprint already logged why
	if (!Blueprint) {
		return nullptr;
	}

	for (int32 EventIndex = 0; EventIndex < Spec.Events.Num(); ++EventIndex) {
		AddNetworkEvent(Blueprint, Spec.Events[EventIndex], EventIndex);
	}

	for (const FModReplicatedVariable& Variable : Spec.Variables) {
		// A variable that can't be added would leave the asset silently incomplete, so stop the build
		if (!AddReplicatedVariable(Blueprint, Variable)) {
			return nullptr;
		}
	}

	// The class defaults only exist once the Blueprint has compiled into a class
	if (!Compile(Blueprint)) {
		return nullptr;
	}
	UObject* DefaultObject = Blueprint->GeneratedClass->GetDefaultObject();

	// The actor has to replicate for its events and variables to cross the network at all
	if (!SetDefaultBool(DefaultObject, TEXT("bReplicates"), true)) {
		return nullptr;
	}
	if (!SetDefaultBool(DefaultObject, TEXT("bOnlyRelevantToOwner"), Spec.bOnlyRelevantToOwner)) {
		return nullptr;
	}

	if (!SaveBlueprint(Blueprint)) {
		return nullptr;
	}

	UE_LOG(LogSpeciesUnknownModKit, Display, TEXT("Built %s: %d network events, %d replicated variables"),
		*Spec.AssetPath, Spec.Events.Num(), Spec.Variables.Num());
	return Blueprint;
}

// ////////////////////// //
//         Assets         //
// ////////////////////// //

UBlueprint* FBlueprintAssetBuilder::CreateFreshBlueprint(const FString& AssetPath, UClass* ParentClass,
	TSubclassOf<UBlueprint> BlueprintClass, TSubclassOf<UBlueprintGeneratedClass> GeneratedClass) {
	// The spec is the only source of truth, so any previous build of this asset is replaced, not updated
	if (UEditorAssetLibrary::DoesAssetExist(AssetPath) && !UEditorAssetLibrary::DeleteAsset(AssetPath)) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Could not delete the previous %s; is it open?"), *AssetPath);
		return nullptr;
	}

	UPackage* Package = CreatePackage(*AssetPath);
	const FName AssetName = FName(FPackageName::GetShortName(AssetPath));
	UBlueprint* Blueprint = FKismetEditorUtilities::CreateBlueprint(ParentClass, Package, AssetName, BPTYPE_Normal,
		BlueprintClass, GeneratedClass);

	// CreateBlueprint only fails for parent classes that can't be subclassed in Blueprint
	if (!Blueprint) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Could not create %s from %s"), *AssetPath,
			*ParentClass->GetName());
		return nullptr;
	}

	FAssetRegistryModule::AssetCreated(Blueprint);
	return Blueprint;
}

bool FBlueprintAssetBuilder::Compile(UBlueprint* Blueprint) {
	FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Blueprint);
	FKismetEditorUtilities::CompileBlueprint(Blueprint);

	// A Blueprint with compile errors keeps a stale or missing class; saving it would ship a broken asset
	if (!Blueprint->GeneratedClass || Blueprint->Status == BS_Error) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("%s failed to compile"), *Blueprint->GetPathName());
		return false;
	}
	return true;
}

bool FBlueprintAssetBuilder::SaveBlueprint(UBlueprint* Blueprint) {
	Blueprint->MarkPackageDirty();
	const bool bSaved = UEditorAssetLibrary::SaveLoadedAsset(Blueprint, false);
	if (!bSaved) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Could not save %s"), *Blueprint->GetPathName());
	}
	return bSaved;
}

// ////////////////////// //
//       Graph parts      //
// ////////////////////// //

void FBlueprintAssetBuilder::AddNetworkEvent(UBlueprint* Blueprint, const FModNetworkEvent& Event, int32 EventIndex) {
	// Network flags per target, matching what the Blueprint editor's "Replicates" dropdown sets
	static const TMap<EModNetworkEventTarget, EFunctionFlags> NetFlagsByTarget = {
		{EModNetworkEventTarget::Server, FUNC_NetServer},
		{EModNetworkEventTarget::OwningClient, FUNC_NetClient},
		{EModNetworkEventTarget::Multicast, FUNC_NetMulticast},
	};

	UEdGraph* EventGraph = FBlueprintEditorUtils::FindEventGraph(Blueprint);
	UK2Node_CustomEvent* EventNode = NewObject<UK2Node_CustomEvent>(EventGraph);
	EventNode->CustomFunctionName = Event.Name;
	EventNode->FunctionFlags |= FUNC_Net | NetFlagsByTarget[Event.Target];
	if (Event.bReliable) {
		EventNode->FunctionFlags |= FUNC_NetReliable;
	}

	EventNode->CreateNewGuid();
	EventNode->NodePosX = 0;
	EventNode->NodePosY = EventIndex * EventNodeSpacing;
	EventGraph->AddNode(EventNode, false, false);
	EventNode->PostPlacedNewNode();
	EventNode->AllocateDefaultPins();

	for (const FModEventParameter& Parameter : Event.Parameters) {
		EventNode->CreateUserDefinedPin(Parameter.Name, Parameter.Type, EGPD_Output, false);
	}
}

bool FBlueprintAssetBuilder::AddReplicatedVariable(UBlueprint* Blueprint, const FModReplicatedVariable& Variable) {
	// AddMemberVariable refuses names that already exist on the class or its parents
	if (!FBlueprintEditorUtils::AddMemberVariable(Blueprint, Variable.Name, Variable.Type)) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Could not add variable %s to %s"), *Variable.Name.ToString(),
			*Blueprint->GetName());
		return false;
	}

	const int32 VariableIndex = FBlueprintEditorUtils::FindNewVariableIndex(Blueprint, Variable.Name);
	FBPVariableDescription& Description = Blueprint->NewVariables[VariableIndex];
	Description.PropertyFlags |= CPF_Net;
	Description.ReplicationCondition = Variable.Condition;
	return true;
}

// ////////////////////// //
//     Class defaults     //
// ////////////////////// //

bool FBlueprintAssetBuilder::SetDefaultBool(UObject* DefaultObject, FName PropertyName, bool bValue) {
	// Actor flags such as bReplicates are not settable through public setters on a class default object, so they
	// are set the way the Class Defaults panel does: through reflection
	FBoolProperty* Property = FindFProperty<FBoolProperty>(DefaultObject->GetClass(), PropertyName);
	if (!Property) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("%s has no bool property %s"), *DefaultObject->GetClass()->GetName(),
			*PropertyName.ToString());
		return false;
	}

	Property->SetPropertyValue_InContainer(DefaultObject, bValue);
	return true;
}

// ////////////////////// //
//        Widgets         //
// ////////////////////// //

UBlueprint* FBlueprintAssetBuilder::BuildWidget(const FModWidgetSpec& Spec) {
	UBlueprint* Blueprint = CreateFreshBlueprint(Spec.AssetPath, UUserWidget::StaticClass(),
		UWidgetBlueprint::StaticClass(), UWidgetBlueprintGeneratedClass::StaticClass());

	// Creating the asset failed; CreateFreshBlueprint already logged why
	if (!Blueprint) {
		return nullptr;
	}

	UWidgetBlueprint* WidgetBlueprint = CastChecked<UWidgetBlueprint>(Blueprint);
	UCanvasPanel* Canvas = WidgetBlueprint->WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(),
		TEXT("Canvas"));
	WidgetBlueprint->WidgetTree->RootWidget = Canvas;

	for (const FModWidgetElement& Element : Spec.Elements) {
		AddWidgetElement(WidgetBlueprint, Canvas, Element);
	}

	if (!Compile(Blueprint) || !SaveBlueprint(Blueprint)) {
		return nullptr;
	}

	UE_LOG(LogSpeciesUnknownModKit, Display, TEXT("Built %s: %d elements"), *Spec.AssetPath, Spec.Elements.Num());
	return Blueprint;
}

void FBlueprintAssetBuilder::AddWidgetElement(UWidgetBlueprint* WidgetBlueprint, UCanvasPanel* Canvas,
	const FModWidgetElement& Element) {
	using FWidgetConstructor = TFunction<UWidget*(UWidgetTree*, const FModWidgetElement&)>;

	// One constructor per element kind; each sets only what its widget type supports
	static const TMap<EModWidgetKind, FWidgetConstructor> ConstructorByKind = {
		{EModWidgetKind::Text, [](UWidgetTree* WidgetTree, const FModWidgetElement& Spec) -> UWidget* {
			UTextBlock* TextBlock = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), Spec.Name);
			TextBlock->SetText(FText::FromString(Spec.Text));
			TextBlock->SetColorAndOpacity(FSlateColor(Spec.Color));
			FSlateFontInfo Font = TextBlock->GetFont();
			Font.Size = Spec.FontSize;
			TextBlock->SetFont(Font);
			// A soft shadow keeps text readable over the game's bright and dark scenes alike
			TextBlock->SetShadowOffset(FVector2D(1.0, 1.0));
			TextBlock->SetShadowColorAndOpacity(FLinearColor(0.0f, 0.0f, 0.0f, 0.75f));
			return TextBlock;
		}},
		{EModWidgetKind::ProgressBar, [](UWidgetTree* WidgetTree, const FModWidgetElement& Spec) -> UWidget* {
			UProgressBar* ProgressBar = WidgetTree->ConstructWidget<UProgressBar>(UProgressBar::StaticClass(),
				Spec.Name);
			ProgressBar->SetPercent(0.0f);
			ProgressBar->SetFillColorAndOpacity(Spec.Color);
			return ProgressBar;
		}},
		{EModWidgetKind::Box, [](UWidgetTree* WidgetTree, const FModWidgetElement& Spec) -> UWidget* {
			UImage* Box = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), Spec.Name);
			Box->SetColorAndOpacity(Spec.Color);
			return Box;
		}},
	};

	UWidget* Widget = ConstructorByKind[Element.Kind](WidgetBlueprint->WidgetTree, Element);

	// Becoming a variable is what makes the element reachable from Lua by name
	Widget->bIsVariable = true;
	if (Element.bHidden) {
		Widget->SetVisibility(ESlateVisibility::Hidden);
	}

	UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(Widget);
	Slot->SetAnchors(Element.Anchors);
	Slot->SetAlignment(Element.Alignment);
	Slot->SetPosition(Element.Position);
	const bool bSizeToContent = Element.Size.IsZero();
	Slot->SetAutoSize(bSizeToContent);
	if (!bSizeToContent) {
		Slot->SetSize(Element.Size);
	}
}
