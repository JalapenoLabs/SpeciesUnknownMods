// Copyright © 2026 Jalapeno Labs

#include "BlueprintAssetBuilder.h"
#include "GameFramework/Actor.h"
#include "ModAssetBuildLibrary.h"
#include "ModKitLog.h"

// The Controllable Entity mod's Blueprint assets, as code. Lua owns all of the mod's behaviour
// (mods/controllable-entity/README.md); these assets only give it what Lua can't create on its own.

namespace {
	// BP_EntityLink: the host spawns one for the entity player, owned by their player controller. It carries the
	// player's actions to the host and the host's replies back. Every event is a bare declaration: UE4SS's
	// RegisterCustomEvent runs Lua when the event executes, on whichever machine that is.
	FModNetworkActorSpec MakeEntityLinkSpec() {
		FModNetworkActorSpec Spec;
		Spec.AssetPath = TEXT("/Game/Mods/ControllableEntity/BP_EntityLink");
		// Only the entity player needs their meter and pings; the crew never receives this actor
		Spec.bOnlyRelevantToOwner = true;

		// Entity player -> host: one action (e.g. "Attack", "Leap", "EnterVent") with where they aimed and what at
		Spec.Events.Add({
			TEXT("ServerCommand"),
			EModNetworkEventTarget::Server,
			true,
			{
				{TEXT("Command"), ModPinTypes::Name()},
				{TEXT("Aim"), ModPinTypes::Vector()},
				{TEXT("Target"), ModPinTypes::Object(AActor::StaticClass())},
			},
		});

		// Host -> entity player: a noise the squid heard. Unreliable: a dropped ping is better than a late one
		Spec.Events.Add({
			TEXT("ClientPing"),
			EModNetworkEventTarget::OwningClient,
			false,
			{
				{TEXT("Location"), ModPinTypes::Vector()},
				{TEXT("Loudness"), ModPinTypes::Float()},
				{TEXT("Kind"), ModPinTypes::Name()},
			},
		});

		// Host -> entity player: a one-off moment for the HUD (e.g. "CooldownStarted", "FrenzyStarted", "Denied")
		Spec.Events.Add({
			TEXT("ClientEvent"),
			EModNetworkEventTarget::OwningClient,
			true,
			{
				{TEXT("Kind"), ModPinTypes::Name()},
				{TEXT("Value"), ModPinTypes::Float()},
			},
		});

		// Continuous state the HUD reads every frame; the host is the only writer
		Spec.Variables.Add({TEXT("Meter"), ModPinTypes::Float(), COND_OwnerOnly});
		Spec.Variables.Add({TEXT("Frenzy"), ModPinTypes::Bool(), COND_OwnerOnly});
		return Spec;
	}
}

bool UModAssetBuildLibrary::BuildControllableEntityAssets() {
	const UBlueprint* EntityLink = FBlueprintAssetBuilder::BuildNetworkActor(MakeEntityLinkSpec());

	// The builder logged the reason; report the mod-level failure so the build script fails loudly
	if (!EntityLink) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Controllable Entity assets failed to build"));
		return false;
	}

	UE_LOG(LogSpeciesUnknownModKit, Display, TEXT("Controllable Entity assets built"));
	return true;
}
