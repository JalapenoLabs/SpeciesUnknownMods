// Copyright © 2026 Jalapeno Labs

#include "BlueprintAssetBuilder.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "EdGraphSchema_K2.h"
#include "EditorAssetLibrary.h"
#include "Engine/Blueprint.h"
#include "GameFramework/Actor.h"
#include "K2Node_CustomEvent.h"
#include "Kismet2/BlueprintEditorUtils.h"
#include "Kismet2/KismetEditorUtilities.h"
#include "ModKitLog.h"
#include "UObject/Package.h"

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
	UBlueprint* Blueprint = CreateFreshBlueprint(Spec.AssetPath, AActor::StaticClass());

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

	FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified(Blueprint);
	FKismetEditorUtilities::CompileBlueprint(Blueprint);

	// The class defaults only exist once the Blueprint has compiled into a class
	if (!Blueprint->GeneratedClass) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("%s compiled without a generated class"), *Spec.AssetPath);
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

UBlueprint* FBlueprintAssetBuilder::CreateFreshBlueprint(const FString& AssetPath, UClass* ParentClass) {
	// The spec is the only source of truth, so any previous build of this asset is replaced, not updated
	if (UEditorAssetLibrary::DoesAssetExist(AssetPath) && !UEditorAssetLibrary::DeleteAsset(AssetPath)) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Could not delete the previous %s; is it open?"), *AssetPath);
		return nullptr;
	}

	UPackage* Package = CreatePackage(*AssetPath);
	const FName AssetName = FName(FPackageName::GetShortName(AssetPath));
	UBlueprint* Blueprint = FKismetEditorUtilities::CreateBlueprint(ParentClass, Package, AssetName, BPTYPE_Normal);

	// CreateBlueprint only fails for parent classes that can't be subclassed in Blueprint
	if (!Blueprint) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Could not create %s from %s"), *AssetPath,
			*ParentClass->GetName());
		return nullptr;
	}

	FAssetRegistryModule::AssetCreated(Blueprint);
	return Blueprint;
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
