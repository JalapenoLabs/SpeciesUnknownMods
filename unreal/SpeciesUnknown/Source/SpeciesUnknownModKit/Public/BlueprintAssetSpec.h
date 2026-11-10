// Copyright © 2026 Jalapeno Labs

#pragma once

#include "CoreMinimal.h"
#include "EdGraph/EdGraphPin.h"
#include "Engine/EngineTypes.h"
#include "Widgets/Layout/Anchors.h"

// Plain descriptions of the Blueprint assets a mod needs. Each mod writes its assets as these specs in code, and
// FBlueprintAssetBuilder turns them into real assets, so the C++ is the single source of truth for every asset.

// ////////////////////// //
//     Network actors     //
// ////////////////////// //

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

// ////////////////////// //
//        Widgets         //
// ////////////////////// //

enum class EModWidgetKind : uint8 {
	Text,
	ProgressBar,
	// A plain coloured rectangle, used for markers.
	Box,
};

// One widget on the widget's canvas. Every element becomes a variable on the generated class under its name, so Lua
// reaches it as `hud.<Name>`.
struct FModWidgetElement {
	FName Name;
	EModWidgetKind Kind = EModWidgetKind::Text;
	// Where on screen the element is pinned (0..1 per axis), and which point of the element sits there.
	FAnchors Anchors = FAnchors(0.5f, 0.5f);
	FVector2D Alignment = FVector2D(0.5f, 0.5f);
	// Offset from the anchor, in pixels.
	FVector2D Position = FVector2D::ZeroVector;
	// Fixed size in pixels; leave zero to size text to its content.
	FVector2D Size = FVector2D::ZeroVector;
	FLinearColor Color = FLinearColor::White;
	FString Text;
	int32 FontSize = 18;
	bool bHidden = false;
};

// A user widget Blueprint made of a single canvas of elements. Lua owns all of its behaviour.
struct FModWidgetSpec {
	FString AssetPath;
	TArray<FModWidgetElement> Elements;
};
