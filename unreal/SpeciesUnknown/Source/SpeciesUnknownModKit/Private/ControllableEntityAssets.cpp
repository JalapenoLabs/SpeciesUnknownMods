// Copyright © 2026 Jalapeno Labs

#include "BlueprintAssetBuilder.h"
#include "GameFramework/Actor.h"
#include "ModAssetBuildLibrary.h"
#include "ModKitLog.h"

// The Controllable Entity mod's Blueprint assets, as code. Lua owns all of the mod's behaviour
// (mods/controllable-entity/README.md); these assets only give it what Lua can't create on its own.

namespace {
	// Number of noise markers the HUD can show at once; older pings are recycled when more arrive.
	constexpr int32 PingMarkerCount = 12;

	// BP_EntityLink: the host spawns one per player, owned by that player's controller. It carries the player's
	// actions to the host and the host's replies back. Every event is a bare declaration: UE4SS's
	// RegisterCustomEvent runs Lua when the event executes, on whichever machine that is. RegisterCustomEvent
	// matches events by name across every class, so each name carries the mod's "Entity" prefix.
	FModNetworkActorSpec MakeEntityLinkSpec() {
		FModNetworkActorSpec Spec;
		Spec.AssetPath = TEXT("/Game/Mods/ControllableEntity/BP_EntityLink");
		// Each player's link reaches only that player: the entity's meter and pings stay private
		Spec.bOnlyRelevantToOwner = true;

		// Player -> host: one action (e.g. "Attack", "Leap", "Vent", "Volunteer") and where the player is looking
		Spec.Events.Add({
			TEXT("EntityServerCommand"),
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
			TEXT("EntityClientPing"),
			EModNetworkEventTarget::OwningClient,
			false,
			{
				{TEXT("Location"), ModPinTypes::Vector()},
				{TEXT("Loudness"), ModPinTypes::Float()},
				{TEXT("Kind"), ModPinTypes::Name()},
			},
		});

		// Host -> player: a one-off moment for the HUD (e.g. "Cooldown", "FrenzyStarted", "Denied", "Volunteered")
		Spec.Events.Add({
			TEXT("EntityClientEvent"),
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

	FModWidgetElement MakeText(FName Name, FAnchors Anchors, FVector2D Alignment, FVector2D Position, int32 FontSize,
		FLinearColor Color, const TCHAR* Text) {
		FModWidgetElement Element;
		Element.Name = Name;
		Element.Kind = EModWidgetKind::Text;
		Element.Anchors = Anchors;
		Element.Alignment = Alignment;
		Element.Position = Position;
		Element.FontSize = FontSize;
		Element.Color = Color;
		Element.Text = Text;
		return Element;
	}

	// WBP_EntityHUD: the entity player's HUD, laid out like a hero shooter's: the ultimate (the kill meter) bottom
	// centre, abilities bottom left, frenzy banner top centre, and a pool of noise markers that Lua positions over
	// the world each frame.
	FModWidgetSpec MakeEntityHudSpec() {
		const FLinearColor Ultimate(1.0f, 0.70f, 0.23f);
		const FLinearColor Frenzy(1.0f, 0.29f, 0.24f);
		const FLinearColor Muted(0.78f, 0.86f, 0.88f);

		FModWidgetSpec Spec;
		Spec.AssetPath = TEXT("/Game/Mods/ControllableEntity/WBP_EntityHUD");

		Spec.Elements.Add(MakeText(TEXT("FrenzyText"), FAnchors(0.5f, 0.0f), FVector2D(0.5f, 0.0f),
			FVector2D(0.0, 64.0), 30, Frenzy, TEXT("")));
		Spec.Elements.Add(MakeText(TEXT("StatusText"), FAnchors(0.5f, 0.62f), FVector2D(0.5f, 0.5f),
			FVector2D::ZeroVector, 22, FLinearColor::White, TEXT("")));
		Spec.Elements.Add(MakeText(TEXT("UltimateText"), FAnchors(0.5f, 1.0f), FVector2D(0.5f, 1.0f),
			FVector2D(0.0, -84.0), 22, Ultimate, TEXT("")));
		Spec.Elements.Add(MakeText(TEXT("AbilityText"), FAnchors(0.0f, 1.0f), FVector2D(0.0f, 1.0f),
			FVector2D(48.0, -48.0), 18, Muted, TEXT("")));

		FModWidgetElement UltimateBar;
		UltimateBar.Name = TEXT("UltimateBar");
		UltimateBar.Kind = EModWidgetKind::ProgressBar;
		UltimateBar.Anchors = FAnchors(0.5f, 1.0f);
		UltimateBar.Alignment = FVector2D(0.5f, 1.0f);
		UltimateBar.Position = FVector2D(0.0, -56.0);
		UltimateBar.Size = FVector2D(420.0, 16.0);
		UltimateBar.Color = Ultimate;
		Spec.Elements.Add(UltimateBar);

		// Markers are positioned in screen pixels from the top-left corner, so they anchor there
		for (int32 PingIndex = 0; PingIndex < PingMarkerCount; ++PingIndex) {
			FModWidgetElement Ping;
			Ping.Name = FName(*FString::Printf(TEXT("Ping%d"), PingIndex));
			Ping.Kind = EModWidgetKind::Box;
			Ping.Anchors = FAnchors(0.0f, 0.0f);
			Ping.Alignment = FVector2D(0.5f, 0.5f);
			Ping.Size = FVector2D(14.0, 14.0);
			Ping.bHidden = true;
			Spec.Elements.Add(Ping);
		}
		return Spec;
	}
}

bool UModAssetBuildLibrary::BuildControllableEntityAssets() {
	// Each builder logs its own failure reason; this reports which mod failed so the build script fails loudly
	if (!FBlueprintAssetBuilder::BuildNetworkActor(MakeEntityLinkSpec())) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Controllable Entity: BP_EntityLink failed to build"));
		return false;
	}
	if (!FBlueprintAssetBuilder::BuildWidget(MakeEntityHudSpec())) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Controllable Entity: WBP_EntityHUD failed to build"));
		return false;
	}

	UE_LOG(LogSpeciesUnknownModKit, Display, TEXT("Controllable Entity assets built"));
	return true;
}
