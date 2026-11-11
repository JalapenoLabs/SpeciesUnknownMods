// Copyright © 2026 Jalapeno Labs

#include "BlueprintAssetBuilder.h"
#include "GameFramework/Actor.h"
#include "Misc/Paths.h"
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

	const FString IconsPath = TEXT("/Game/Mods/ControllableEntity/Icons");

	// The HUD's icons, by asset name and SVG source (mods/controllable-entity/art/icons/<source>.svg), which
	// scripts/build-mod-assets.sh renders to Saved/ModArt/controllable-entity/<source>.png before the editor starts.
	struct FIconSource {
		const TCHAR* Name;
		const TCHAR* SourceName;
	};
	const FIconSource IconSources[] = {
		{TEXT("Lash"), TEXT("lash")},
		{TEXT("Leap"), TEXT("leap")},
		{TEXT("Vent"), TEXT("vent")},
		{TEXT("Peek"), TEXT("peek")},
		{TEXT("View"), TEXT("view")},
		{TEXT("HeadGrab"), TEXT("head-grab")},
	};

	FString IconAssetPath(const TCHAR* IconName) {
		return IconsPath / FString::Printf(TEXT("T_Icon_%s"), IconName);
	}

	TArray<FModTextureSpec> MakeIconSpecs() {
		const FString RenderedIconsDirectory = FPaths::ConvertRelativePathToFull(
			FPaths::ProjectSavedDir() / TEXT("ModArt/controllable-entity"));

		TArray<FModTextureSpec> Specs;
		for (const FIconSource& Icon : IconSources) {
			FModTextureSpec Spec;
			Spec.SourceFile = RenderedIconsDirectory / FString(Icon.SourceName) + TEXT(".png");
			Spec.AssetPath = IconAssetPath(Icon.Name);
			Specs.Add(Spec);
		}
		return Specs;
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

	// One ability the way the game shows its own (the flashlight): an icon, the key in a rounded white box, and a bar
	// to the right that Lua shows while the ability recharges. Lua reaches the parts as <Prefix>Icon, <Prefix>Key and
	// <Prefix>KeyText, <Prefix>Bar, and dims the whole <Prefix>Slot while the ability can't be used. The key label is
	// a placeholder: Lua sets it.
	FModWidgetElement MakeAbilitySlot(const TCHAR* Prefix, const TCHAR* IconName, const TCHAR* KeyLabel,
		double IconSize, FVector2D BarSize, FLinearColor BarColor, int32 KeyFontSize) {
		FModWidgetElement Icon;
		Icon.Name = FName(FString(Prefix) + TEXT("Icon"));
		Icon.Kind = EModWidgetKind::Image;
		Icon.TexturePath = IconAssetPath(IconName);
		Icon.Size = FVector2D(IconSize, IconSize);

		FModWidgetElement Key;
		Key.Name = FName(FString(Prefix) + TEXT("Key"));
		Key.Kind = EModWidgetKind::KeyCap;
		Key.Text = KeyLabel;
		Key.FontSize = KeyFontSize;

		FModWidgetElement Bar;
		Bar.Name = FName(FString(Prefix) + TEXT("Bar"));
		Bar.Kind = EModWidgetKind::ProgressBar;
		Bar.Size = BarSize;
		Bar.Color = BarColor;

		FModWidgetElement Slot;
		Slot.Name = FName(FString(Prefix) + TEXT("Slot"));
		Slot.Kind = EModWidgetKind::Row;
		Slot.Gap = 8.0f;
		Slot.Children = {Icon, Key, Bar};
		return Slot;
	}

	// WBP_EntityHUD: the entity player's HUD, along the top of the screen. Abilities run along the top left, the
	// ultimate (the kill meter) sits top centre with its percentage, the frenzy banner and the host's messages below
	// it, and a pool of noise markers that Lua positions over the world each frame.
	FModWidgetSpec MakeEntityHudSpec() {
		const FLinearColor Ultimate(1.0f, 0.70f, 0.23f);
		const FLinearColor Frenzy(1.0f, 0.29f, 0.24f);
		const FLinearColor Cooldown(0.92f, 0.95f, 0.96f);

		FModWidgetSpec Spec;
		Spec.AssetPath = TEXT("/Game/Mods/ControllableEntity/WBP_EntityHUD");

		const FVector2D AbilityBarSize(44.0, 6.0);
		FModWidgetElement Abilities;
		Abilities.Name = TEXT("Abilities");
		Abilities.Kind = EModWidgetKind::Row;
		Abilities.Anchors = FAnchors(0.0f, 0.0f);
		Abilities.Alignment = FVector2D(0.0f, 0.0f);
		Abilities.Position = FVector2D(40.0, 36.0);
		Abilities.Gap = 22.0f;
		Abilities.Children = {
			MakeAbilitySlot(TEXT("Lash"), TEXT("Lash"), TEXT("LMB"), 36.0, AbilityBarSize, Cooldown, 14),
			MakeAbilitySlot(TEXT("Leap"), TEXT("Leap"), TEXT("RMB"), 36.0, AbilityBarSize, Cooldown, 14),
			MakeAbilitySlot(TEXT("Vent"), TEXT("Vent"), TEXT("E"), 36.0, AbilityBarSize, Cooldown, 14),
			MakeAbilitySlot(TEXT("Peek"), TEXT("Peek"), TEXT("C"), 36.0, AbilityBarSize, Cooldown, 14),
			MakeAbilitySlot(TEXT("View"), TEXT("View"), TEXT("F"), 36.0, AbilityBarSize, Cooldown, 14),
		};
		Spec.Elements.Add(Abilities);

		FModWidgetElement UltimateSlot = MakeAbilitySlot(TEXT("Ultimate"), TEXT("HeadGrab"), TEXT("SPACE"), 44.0,
			FVector2D(260.0, 10.0), Ultimate, 15);
		UltimateSlot.Anchors = FAnchors(0.5f, 0.0f);
		UltimateSlot.Alignment = FVector2D(0.5f, 0.0f);
		UltimateSlot.Position = FVector2D(0.0, 30.0);
		Spec.Elements.Add(UltimateSlot);

		const FAnchors TopCentre(0.5f, 0.0f);
		const FVector2D HangBelow(0.5f, 0.0f);
		Spec.Elements.Add(MakeText(TEXT("UltimateText"), TopCentre, HangBelow, FVector2D(0.0, 86.0), 18, Ultimate,
			TEXT("")));
		Spec.Elements.Add(MakeText(TEXT("FrenzyText"), TopCentre, HangBelow, FVector2D(0.0, 114.0), 26, Frenzy,
			TEXT("")));
		Spec.Elements.Add(MakeText(TEXT("StatusText"), TopCentre, HangBelow, FVector2D(0.0, 156.0), 22,
			FLinearColor::White, TEXT("")));

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
	// Each builder logs its own failure reason; this reports which asset failed so the build script fails loudly.
	// Textures come first: the HUD widget points at them
	for (const FModTextureSpec& IconSpec : MakeIconSpecs()) {
		if (!FBlueprintAssetBuilder::BuildTexture(IconSpec)) {
			UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Controllable Entity: %s failed to build"), *IconSpec.AssetPath);
			return false;
		}
	}

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
