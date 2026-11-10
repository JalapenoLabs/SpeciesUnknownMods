// Copyright © 2026 Jalapeno Labs

#pragma once

#include "CoreMinimal.h"
#include "BlueprintAssetSpec.h"

class UBlueprint;
class UBlueprintGeneratedClass;

// Turns asset specs into saved Blueprint assets. Every build replaces the asset from scratch, so an asset never
// keeps anything its spec doesn't describe.
class SPECIESUNKNOWNMODKIT_API FBlueprintAssetBuilder {
public:
	// Each returns the saved Blueprint, or nullptr after logging why the build failed.
	static UBlueprint* BuildNetworkActor(const FModNetworkActorSpec& Spec);
	static UBlueprint* BuildWidget(const FModWidgetSpec& Spec);

private:
	// ////////////////////// //
	//        Assets          //
	// ////////////////////// //

	// Replaces any previous build of the asset with a new, empty Blueprint of the given kind
	static UBlueprint* CreateFreshBlueprint(const FString& AssetPath, UClass* ParentClass,
		TSubclassOf<UBlueprint> BlueprintClass, TSubclassOf<UBlueprintGeneratedClass> GeneratedClass);
	// Compiles, then checks the Blueprint produced a class; returns false after logging otherwise
	static bool Compile(UBlueprint* Blueprint);
	static bool SaveBlueprint(UBlueprint* Blueprint);

	// ////////////////////// //
	//       Graph parts      //
	// ////////////////////// //

	static void AddNetworkEvent(UBlueprint* Blueprint, const FModNetworkEvent& Event, int32 EventIndex);
	static bool AddReplicatedVariable(UBlueprint* Blueprint, const FModReplicatedVariable& Variable);

	// ////////////////////// //
	//      Widget parts      //
	// ////////////////////// //

	static void AddWidgetElement(class UWidgetBlueprint* WidgetBlueprint, class UCanvasPanel* Canvas,
		const FModWidgetElement& Element);

	// ////////////////////// //
	//     Class defaults     //
	// ////////////////////// //

	static bool SetDefaultBool(UObject* DefaultObject, FName PropertyName, bool bValue);
};
