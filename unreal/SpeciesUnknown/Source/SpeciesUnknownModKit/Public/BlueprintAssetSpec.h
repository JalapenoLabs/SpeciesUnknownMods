// Copyright © 2026 Jalapeno Labs

#pragma once

#include "CoreMinimal.h"
#include "EdGraph/EdGraphPin.h"
#include "Engine/EngineTypes.h"

// Plain descriptions of the Blueprint assets a mod needs. Each mod writes its assets as these specs in code, and
// FBlueprintAssetBuilder turns them into real assets, so the C++ is the single source of truth for every asset.

// Which machine a network event runs on, mirroring the Blueprint editor's "Replicates" dropdown.
enum class EModNetworkEventTarget : uint8 {
	Server,
	OwningClient,
	Multicast,
};

struct FModEventParameter {
	FName Name;
	FEdGraphPinType Type;
};

// A custom event that the engine sends over the network. It has no logic of its own: Lua runs when it executes,
// through UE4SS's RegisterCustomEvent.
struct FModNetworkEvent {
	FName Name;
	EModNetworkEventTarget Target = EModNetworkEventTarget::Server;
	bool bReliable = true;
	TArray<FModEventParameter> Parameters;
};

struct FModReplicatedVariable {
	FName Name;
	FEdGraphPinType Type;
	ELifetimeCondition Condition = COND_None;
};

// An actor Blueprint that exists to carry network events and replicated state between machines.
struct FModNetworkActorSpec {
	// Long package path, e.g. "/Game/Mods/ControllableEntity/BP_EntityLink".
	FString AssetPath;
	// Only the owning player's machine receives the actor, for state no one else should see.
	bool bOnlyRelevantToOwner = false;
	TArray<FModNetworkEvent> Events;
	TArray<FModReplicatedVariable> Variables;
};

// Pin types for the parameter and variable lists above, so specs read as plain declarations.
namespace ModPinTypes {
	SPECIESUNKNOWNMODKIT_API FEdGraphPinType Bool();
	SPECIESUNKNOWNMODKIT_API FEdGraphPinType Float();
	SPECIESUNKNOWNMODKIT_API FEdGraphPinType Name();
	SPECIESUNKNOWNMODKIT_API FEdGraphPinType Vector();
	SPECIESUNKNOWNMODKIT_API FEdGraphPinType Object(UClass* ObjectClass);
}
