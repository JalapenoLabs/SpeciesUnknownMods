// Copyright © 2026 Jalapeno Labs

#include "BlueprintAssetBuilder.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/Image.h"
#include "Components/ProgressBar.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "EdGraphSchema_K2.h"
#include "EditorAssetLibrary.h"
#include "Engine/Blueprint.h"
#include "Engine/Texture2D.h"
#include "GameFramework/Actor.h"
#include "ImageCore.h"
#include "ImageUtils.h"
#include "K2Node_CustomEvent.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "ModKitLog.h"
#include "UObject/Package.h"
#include "WidgetBlueprint.h"
#include "Blueprint/WidgetBlueprintGeneratedClass.h"

// Vertical spacing between generated event nodes, so the graph stays readable when opened in the editor.
static constexpr int32 EventNodeSpacing = 200;

// Key caps copy the game's own key prompts: dark bold text in a white box with rounded corners.
static constexpr float KeyCapCornerRadius = 5.0f;
static const FMargin KeyCapPadding(8.0f, 2.0f);
static const FLinearColor KeyCapTextColor(0.04f, 0.04f, 0.05f);
// Progress bars sit on the dark blue-grey track every bar of the crew HUD shares (UI_HUD_Display's cooked bars), so
// they read over the game's bright and dark scenes alike.
static const FLinearColor ProgressTrackColor(0.063f, 0.102f, 0.12f, 0.75f);

namespace {
	// A solid brush with rounded corners, drawn by Slate itself (no texture needed).
	FSlateBrush MakeRoundedBrush(const FLinearColor& Color, float CornerRadius) {
		FSlateBrush Brush;
		Brush.DrawAs = ESlateBrushDrawType::RoundedBox;
		Brush.TintColor = FSlateColor(Color);
		Brush.OutlineSettings = FSlateBrushOutlineSettings(FVector4(CornerRadius, CornerRadius, CornerRadius,
			CornerRadius), FSlateColor(Color), 0.0f);
		Brush.OutlineSettings.RoundingType = ESlateBrushRoundingType::FixedRadius;
		return Brush;
	}

	// A text style shared by every text element: a size, a typeface ("Regular", "Bold") and a soft shadow that keeps
	// it readable over any scene.
	void StyleText(UTextBlock* TextBlock, int32 FontSize, FName Typeface, bool bShadow) {
		FSlateFontInfo Font = TextBlock->GetFont();
		Font.Size = FontSize;
		Font.TypefaceFontName = Typeface;
		TextBlock->SetFont(Font);
		if (bShadow) {
			TextBlock->SetShadowOffset(FVector2D(1.0, 1.0));
			TextBlock->SetShadowColorAndOpacity(FLinearColor(0.0f, 0.0f, 0.0f, 0.75f));
		}
	}
}

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
		// An element that can't be built (a missing texture) would ship a HUD with a hole in it
		if (!AddWidgetElement(WidgetBlueprint, Canvas, Element)) {
			return nullptr;
		}
	}

	if (!Compile(Blueprint) || !SaveBlueprint(Blueprint)) {
		return nullptr;
	}

	UE_LOG(LogSpeciesUnknownModKit, Display, TEXT("Built %s: %d elements"), *Spec.AssetPath, Spec.Elements.Num());
	return Blueprint;
}

bool FBlueprintAssetBuilder::AddWidgetElement(UWidgetBlueprint* WidgetBlueprint, UCanvasPanel* Canvas,
	const FModWidgetElement& Element) {
	UWidget* Widget = ConstructElement(WidgetBlueprint->WidgetTree, Element);

	// ConstructElement already logged what was missing
	if (!Widget) {
		return false;
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
	return true;
}

UWidget* FBlueprintAssetBuilder::ConstructElement(UWidgetTree* WidgetTree, const FModWidgetElement& Element) {
	using FElementConstructor = UWidget* (*)(UWidgetTree*, const FModWidgetElement&);

	// One constructor per element kind; each sets only what its widget type supports
	static const TMap<EModWidgetKind, FElementConstructor> ConstructorByKind = {
		{EModWidgetKind::Text, &FBlueprintAssetBuilder::ConstructText},
		{EModWidgetKind::ProgressBar, &FBlueprintAssetBuilder::ConstructProgressBar},
		{EModWidgetKind::Box, &FBlueprintAssetBuilder::ConstructBox},
		{EModWidgetKind::Image, &FBlueprintAssetBuilder::ConstructImage},
		{EModWidgetKind::KeyCap, &FBlueprintAssetBuilder::ConstructKeyCap},
		{EModWidgetKind::Row, &FBlueprintAssetBuilder::ConstructRow},
		{EModWidgetKind::Column, &FBlueprintAssetBuilder::ConstructColumn},
	};

	UWidget* Widget = ConstructorByKind[Element.Kind](WidgetTree, Element);

	// The constructor logged what was missing
	if (!Widget) {
		return nullptr;
	}

	// Becoming a variable is what makes the element reachable from Lua by name
	Widget->bIsVariable = true;
	if (Element.bHidden) {
		Widget->SetVisibility(ESlateVisibility::Hidden);
	}
	return Widget;
}

UWidget* FBlueprintAssetBuilder::ConstructText(UWidgetTree* WidgetTree, const FModWidgetElement& Element) {
	UTextBlock* TextBlock = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), Element.Name);
	TextBlock->SetText(FText::FromString(Element.Text));
	TextBlock->SetColorAndOpacity(FSlateColor(Element.Color));
	TextBlock->SetJustification(ETextJustify::Center);
	StyleText(TextBlock, Element.FontSize, TEXT("Regular"), true);
	return TextBlock;
}

UWidget* FBlueprintAssetBuilder::ConstructProgressBar(UWidgetTree* WidgetTree, const FModWidgetElement& Element) {
	UProgressBar* ProgressBar = WidgetTree->ConstructWidget<UProgressBar>(UProgressBar::StaticClass(), Element.Name);

	// Fully rounded ends, like the game's own bars
	const float CornerRadius = static_cast<float>(Element.Size.Y) / 2.0f;
	FProgressBarStyle Style = ProgressBar->GetWidgetStyle();
	Style.SetBackgroundImage(MakeRoundedBrush(ProgressTrackColor, CornerRadius));
	Style.SetFillImage(MakeRoundedBrush(FLinearColor::White, CornerRadius));
	ProgressBar->SetWidgetStyle(Style);

	ProgressBar->SetPercent(0.0f);
	ProgressBar->SetFillColorAndOpacity(Element.Color);
	return ProgressBar;
}

UWidget* FBlueprintAssetBuilder::ConstructBox(UWidgetTree* WidgetTree, const FModWidgetElement& Element) {
	UImage* Box = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), Element.Name);
	Box->SetColorAndOpacity(Element.Color);
	return Box;
}

UWidget* FBlueprintAssetBuilder::ConstructImage(UWidgetTree* WidgetTree, const FModWidgetElement& Element) {
	const FString ObjectPath = Element.TexturePath + TEXT(".") + FPackageName::GetShortName(Element.TexturePath);
	UTexture2D* Texture = LoadObject<UTexture2D>(nullptr, *ObjectPath);

	// Textures build before the widgets that use them; a missing one means its build failed or wasn't listed
	if (!Texture) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("%s needs the texture %s, which isn't built"),
			*Element.Name.ToString(), *Element.TexturePath);
		return nullptr;
	}

	UImage* Image = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), Element.Name);
	FSlateBrush Brush;
	Brush.SetResourceObject(Texture);
	Brush.ImageSize = Element.Size;
	Image->SetBrush(Brush);
	Image->SetColorAndOpacity(Element.Color);
	return Image;
}

UWidget* FBlueprintAssetBuilder::ConstructKeyCap(UWidgetTree* WidgetTree, const FModWidgetElement& Element) {
	UBorder* KeyCap = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), Element.Name);
	KeyCap->SetBrush(MakeRoundedBrush(FLinearColor::White, KeyCapCornerRadius));
	KeyCap->SetPadding(KeyCapPadding);
	KeyCap->SetHorizontalAlignment(HAlign_Center);
	KeyCap->SetVerticalAlignment(VAlign_Center);

	const FName LabelName(Element.Name.ToString() + TEXT("Text"));
	UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), LabelName);
	Label->SetText(FText::FromString(Element.Text));
	Label->SetColorAndOpacity(FSlateColor(KeyCapTextColor));
	Label->SetJustification(ETextJustify::Center);
	StyleText(Label, Element.FontSize, TEXT("Bold"), false);
	// Lua sets the label from the player's keys, so it must be reachable by name too
	Label->bIsVariable = true;
	KeyCap->SetContent(Label);
	return KeyCap;
}

UWidget* FBlueprintAssetBuilder::ConstructSizedChild(UWidgetTree* WidgetTree, const FModWidgetElement& Child) {
	UWidget* ChildWidget = ConstructElement(WidgetTree, Child);

	// ConstructElement logged what was missing
	if (!ChildWidget || Child.Size.IsZero()) {
		return ChildWidget;
	}

	// A fixed size holds the child's space even while Lua hides it, so the rest of the row or column never shifts
	USizeBox* SizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(),
		FName(Child.Name.ToString() + TEXT("Size")));
	SizeBox->SetWidthOverride(Child.Size.X);
	SizeBox->SetHeightOverride(Child.Size.Y);
	SizeBox->SetContent(ChildWidget);
	return SizeBox;
}

UWidget* FBlueprintAssetBuilder::ConstructColumn(UWidgetTree* WidgetTree, const FModWidgetElement& Element) {
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), Element.Name);

	for (int32 ChildIndex = 0; ChildIndex < Element.Children.Num(); ++ChildIndex) {
		UWidget* PlacedWidget = ConstructSizedChild(WidgetTree, Element.Children[ChildIndex]);

		// The child's construction logged what was missing; a column with a hole in it isn't worth shipping
		if (!PlacedWidget) {
			return nullptr;
		}

		UVerticalBoxSlot* Slot = Column->AddChildToVerticalBox(PlacedWidget);
		Slot->SetHorizontalAlignment(HAlign_Left);
		const float LeadingGap = ChildIndex == 0 ? 0.0f : Element.Gap;
		Slot->SetPadding(FMargin(0.0f, LeadingGap, 0.0f, 0.0f));
	}
	return Column;
}

UWidget* FBlueprintAssetBuilder::ConstructRow(UWidgetTree* WidgetTree, const FModWidgetElement& Element) {
	UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), Element.Name);

	for (int32 ChildIndex = 0; ChildIndex < Element.Children.Num(); ++ChildIndex) {
		UWidget* PlacedWidget = ConstructSizedChild(WidgetTree, Element.Children[ChildIndex]);

		// The child's construction logged what was missing; a row with a hole in it isn't worth shipping
		if (!PlacedWidget) {
			return nullptr;
		}

		UHorizontalBoxSlot* Slot = Row->AddChildToHorizontalBox(PlacedWidget);
		Slot->SetVerticalAlignment(VAlign_Center);
		const float LeadingGap = ChildIndex == 0 ? 0.0f : Element.Gap;
		Slot->SetPadding(FMargin(LeadingGap, 0.0f, 0.0f, 0.0f));
	}
	return Row;
}

// ////////////////////// //
//        Textures        //
// ////////////////////// //

UTexture2D* FBlueprintAssetBuilder::BuildTexture(const FModTextureSpec& Spec) {
	// The PNGs are rendered by scripts/build-mod-assets.sh before the editor starts; without one there's nothing to
	// build from
	FImage SourceImage;
	if (!FImageUtils::LoadImage(*Spec.SourceFile, SourceImage)) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Could not read a PNG at %s for %s; run scripts/build-mod-assets.sh"),
			*Spec.SourceFile, *Spec.AssetPath);
		return nullptr;
	}

	// The texture is filled from the PNG's pixels directly rather than through the editor's importer, which in UE 5.7
	// (Interchange) reports its results through Slate and crashes a headless editor. A previous build's texture is
	// reused, so the widgets that point at it stay linked; everything about it is set again below
	const FString ShortName = FPackageName::GetShortName(Spec.AssetPath);
	UTexture2D* Texture = LoadObject<UTexture2D>(nullptr, *(Spec.AssetPath + TEXT(".") + ShortName), nullptr,
		LOAD_NoWarn | LOAD_Quiet);
	if (!Texture) {
		UPackage* Package = CreatePackage(*Spec.AssetPath);
		Texture = NewObject<UTexture2D>(Package, FName(ShortName), RF_Public | RF_Standalone);
		FAssetRegistryModule::AssetCreated(Texture);
	}

	Texture->PreEditChange(nullptr);
	Texture->Source.Init(SourceImage);
	// HUD icons are drawn at one fixed size: no mips, no streaming, and uncompressed so their edges stay crisp
	Texture->CompressionSettings = TC_EditorIcon;
	Texture->LODGroup = TEXTUREGROUP_UI;
	Texture->MipGenSettings = TMGS_NoMipmaps;
	Texture->NeverStream = true;
	Texture->SRGB = true;
	Texture->PostEditChange();
	Texture->MarkPackageDirty();

	if (!UEditorAssetLibrary::SaveLoadedAsset(Texture, false)) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Could not save %s"), *Spec.AssetPath);
		return nullptr;
	}

	UE_LOG(LogSpeciesUnknownModKit, Display, TEXT("Built %s from %s (%dx%d)"), *Spec.AssetPath, *Spec.SourceFile,
		SourceImage.SizeX, SourceImage.SizeY);
	return Texture;
}
