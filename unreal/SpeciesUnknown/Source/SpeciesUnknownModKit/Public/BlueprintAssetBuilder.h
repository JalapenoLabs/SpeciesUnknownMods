// Copyright © 2026 Jalapeno Labs

#pragma once

#include "CoreMinimal.h"
#include "BlueprintAssetSpec.h"

class UBlueprint;

// Turns asset specs into saved Blueprint assets. Every build replaces the asset from scratch, so an asset never
// keeps anything its spec doesn't describe.
class SPECIESUNKNOWNMODKIT_API FBlueprintAssetBuilder {
public:
	// Returns the saved Blueprint, or nullptr after logging why the build failed.
	static UBlueprint* BuildNetworkActor(const FModNetworkActorSpec& Spec);

private:
	// ////////////////////// //
	//        Assets          //
	// ////////////////////// //

	static UBlueprint* CreateFreshBlueprint(const FString& AssetPath, UClass* ParentClass);
	static bool SaveBlueprint(UBlueprint* Blueprint);

	// ////////////////////// //
	//       Graph parts      //
	// ////////////////////// //

	static void AddNetworkEvent(UBlueprint* Blueprint, const FModNetworkEvent& Event, int32 EventIndex);
	static bool AddReplicatedVariable(UBlueprint* Blueprint, const FModReplicatedVariable& Variable);

	// ////////////////////// //
	//     Class defaults     //
	// ////////////////////// //

	static bool SetDefaultBool(UObject* DefaultObject, FName PropertyName, bool bValue);
};
