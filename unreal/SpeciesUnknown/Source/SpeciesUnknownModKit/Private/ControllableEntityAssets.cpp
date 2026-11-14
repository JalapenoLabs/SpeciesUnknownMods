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

		// Player -> host: one action (e.g. "Primary", "Ultimate", "Peek", "Volunteer") and where the player is looking
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

		// Host -> entity player: a noise the entity heard. Unreliable: a dropped ping is better than a late one
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

		// Host -> player: a one-off moment for the HUD (e.g. "Cooldown.Primary" with its seconds, "FrenzyStarted",
		// "Denied.NoTarget", "Volunteered")
		Spec.Events.Add({
			TEXT("EntityClientEvent"),
			EModNetworkEventTarget::OwningClient,
			true,
			{
				{TEXT("Kind"), ModPinTypes::Name()},
				{TEXT("Value"), ModPinTypes::Float()},
			},
		});

		// Continuous state the HUD reads every frame; the host is the only writer. Health is the fraction left of the pool
		// hits are draining (the squid's stagger pool while standing, its real health while Downed; Mike's one pool). A
		// monster's own health doesn't replicate, so the host sends it here
		Spec.Variables.Add({TEXT("Meter"), ModPinTypes::Float(), COND_OwnerOnly});
		Spec.Variables.Add({TEXT("Frenzy"), ModPinTypes::Bool(), COND_OwnerOnly});
		Spec.Variables.Add({TEXT("Health"), ModPinTypes::Float(), COND_OwnerOnly});
		Spec.Variables.Add({TEXT("Downed"), ModPinTypes::Bool(), COND_OwnerOnly});
		Spec.Variables.Add({TEXT("Stamina"), ModPinTypes::Float(), COND_OwnerOnly});
		// How much of the entity's time in the vents is left, 0 to 1, once the crew holds the weapon that can kill it
		Spec.Variables.Add({TEXT("VentTime"), ModPinTypes::Float(), COND_OwnerOnly});
		return Spec;
	}

	const FString IconsPath = TEXT("/Game/Mods/ControllableEntity/Icons");

	// The HUD's icons, by asset name and SVG source (mods/controllable-entity/art/icons/<source>.svg), which
	// scripts/build-mod-assets.sh renders to Saved/ModArt/controllable-entity/<source>.png before the editor starts.
	// Every entity's moves have one, by the name its kit gives (kits/<name>.lua, moves.<slot>.icon), which Lua loads
	// into the action stack's slots for the entity being played.
	struct FIconSource {
		const TCHAR* Name;
		const TCHAR* SourceName;
	};
	const FIconSource IconSources[] = {
		{TEXT("Lash"), TEXT("lash")},
		{TEXT("Leap"), TEXT("leap")},
		{TEXT("Vent"), TEXT("vent")},
		{TEXT("HeadGrab"), TEXT("head-grab")},
		{TEXT("Swipe"), TEXT("swipe")},
		{TEXT("Dodge"), TEXT("dodge")},
		{TEXT("Devour"), TEXT("devour")},
		{TEXT("Gatling"), TEXT("gatling")},
		{TEXT("Grenade"), TEXT("grenade")},
		{TEXT("ArmGrab"), TEXT("arm-grab")},
		{TEXT("Dash"), TEXT("dash")},
		{TEXT("ViewCone"), TEXT("view-cone")},
		{TEXT("Random"), TEXT("random")},
		{TEXT("Player"), TEXT("player")},
		{TEXT("AiOnly"), TEXT("ai-only")},
		{TEXT("PulseRing"), TEXT("pulse-ring")},
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

	FModWidgetElement MakeBar(const TCHAR* Name, FVector2D Size, FLinearColor Color) {
		FModWidgetElement Bar;
		Bar.Name = Name;
		Bar.Kind = EModWidgetKind::ProgressBar;
		Bar.Size = Size;
		Bar.Color = Color;
		return Bar;
	}

	// A key glyph: an image Lua fills with the game's own glyph for the key (its /Game/KeyIcons textures, as its "press
	// E" prompts show) and sizes to that texture, inside a fixed space so what follows lines up. It sits against the
	// space's right side, next to what it names.
	FModWidgetElement MakeKeyGlyph(const TCHAR* Name, FVector2D Space) {
		FModWidgetElement Glyph;
		Glyph.Name = Name;
		Glyph.Kind = EModWidgetKind::Image;
		Glyph.Size = Space;
		Glyph.ContentAlignment = HAlign_Right;
		return Glyph;
	}

	// One action in the stack (playtest 7): its key, its icon, and a bar on the right that Lua shows while the action
	// recharges (its space stays reserved, so the stack never shifts). Lua reaches the parts as <Prefix>Key,
	// <Prefix>Icon and <Prefix>Bar, and dims the whole <Prefix>Slot while the action can't be used. The icon built in
	// is the squid's; Lua swaps in the icon of the move the entity being played has in that slot.
	FModWidgetElement MakeActionSlot(const TCHAR* Prefix, const TCHAR* IconName, FLinearColor BarColor) {
		FModWidgetElement Icon;
		Icon.Name = FName(FString(Prefix) + TEXT("Icon"));
		Icon.Kind = EModWidgetKind::Image;
		Icon.TexturePath = IconAssetPath(IconName);
		Icon.Size = FVector2D(34.0, 34.0);

		FModWidgetElement Slot;
		Slot.Name = FName(FString(Prefix) + TEXT("Slot"));
		Slot.Kind = EModWidgetKind::Row;
		Slot.Gap = 10.0f;
		Slot.Children = {
			MakeKeyGlyph(*(FString(Prefix) + TEXT("Key")), FVector2D(72.0, 32.0)),
			Icon,
			MakeBar(*(FString(Prefix) + TEXT("Bar")), FVector2D(56.0, 6.0), BarColor),
		};
		return Slot;
	}

	// A label inside a row, which places it
	FModWidgetElement MakeLabel(const TCHAR* Name, const TCHAR* Text, int32 FontSize, FLinearColor Color) {
		FModWidgetElement Label;
		Label.Name = Name;
		Label.Kind = EModWidgetKind::Text;
		Label.Text = Text;
		Label.FontSize = FontSize;
		Label.Color = Color;
		return Label;
	}

	// One key hint under the minimap: the key's glyph and what it does, as <Name>Key and <Name>Label inside <Name>.
	FModWidgetElement MakeKeyHint(const TCHAR* Name, const TCHAR* Label, FLinearColor Color) {
		FModWidgetElement Hint;
		Hint.Name = Name;
		Hint.Kind = EModWidgetKind::Row;
		Hint.Gap = 6.0f;
		Hint.Children = {
			MakeKeyGlyph(*(FString(Name) + TEXT("Key")), FVector2D(44.0, 22.0)),
			MakeLabel(*(FString(Name) + TEXT("Label")), Label, 12, Color),
		};
		return Hint;
	}


	// WBP_EntityHUD: the entity player's HUD, laid out like the crew's own. Bottom left: the entity's four moves
	// stacked vertically (its slots, kits.slots), with the health and stamina bars below them. Top right: the minimap
	// (the game's own widget, which Lua adds) with a view cone over it and the key hints under it. Top centre: the vent
	// time, while the crew hunts the entity. Bottom centre: the frenzy banner and the host's messages. Bottom right:
	// the crew's respawns left. Noise markers are positioned over the world by Lua each frame.
	FModWidgetSpec MakeEntityHudSpec() {
		const FLinearColor Ultimate(1.0f, 0.70f, 0.23f);
		const FLinearColor Frenzy(1.0f, 0.29f, 0.24f);
		// The crew HUD's own fills (UI_HUD_Display's cooked bars): its flashlight and tool bars' pale blue-grey for
		// the recharging actions, its health green, and its half-white stamina
		const FLinearColor Cooldown(0.584f, 0.708f, 0.768f);
		const FLinearColor Health(0.025f, 0.25f, 0.119f, 0.75f);
		const FLinearColor Stamina(1.0f, 1.0f, 1.0f, 0.5f);
		const FLinearColor Hint(0.82f, 0.86f, 0.88f);

		FModWidgetSpec Spec;
		Spec.AssetPath = TEXT("/Game/Mods/ControllableEntity/WBP_EntityHUD");

		const FAnchors BottomLeft(0.0f, 1.0f);
		const FVector2D SitOnCorner(0.0f, 1.0f);

		FModWidgetElement Actions;
		Actions.Name = TEXT("Actions");
		Actions.Kind = EModWidgetKind::Column;
		Actions.Anchors = BottomLeft;
		Actions.Alignment = SitOnCorner;
		Actions.Position = FVector2D(56.0, -92.0);
		Actions.Gap = 10.0f;
		Actions.Children = {
			MakeActionSlot(TEXT("Primary"), TEXT("Lash"), Cooldown),
			MakeActionSlot(TEXT("Secondary"), TEXT("Leap"), Cooldown),
			MakeActionSlot(TEXT("Ultimate"), TEXT("HeadGrab"), Ultimate),
			MakeActionSlot(TEXT("Mobility"), TEXT("Vent"), Cooldown),
		};
		Spec.Elements.Add(Actions);

		FModWidgetElement HealthBar = MakeBar(TEXT("HealthBar"), FVector2D(300.0, 12.0), Health);
		HealthBar.Anchors = BottomLeft;
		HealthBar.Alignment = SitOnCorner;
		HealthBar.Position = FVector2D(56.0, -64.0);
		Spec.Elements.Add(HealthBar);

		FModWidgetElement StaminaBar = MakeBar(TEXT("StaminaBar"), FVector2D(300.0, 6.0), Stamina);
		StaminaBar.Anchors = BottomLeft;
		StaminaBar.Alignment = SitOnCorner;
		StaminaBar.Position = FVector2D(56.0, -48.0);
		Spec.Elements.Add(StaminaBar);

		// The view cone and the key hints go over and under the minimap, which Lua adds and sizes (minimap.lua), so Lua
		// places them from the same settings; anchored top right, the corner the minimap sits in. Lua turns the cone with
		// the player's look
		FModWidgetElement ViewCone;
		ViewCone.Name = TEXT("ViewCone");
		ViewCone.Kind = EModWidgetKind::Image;
		ViewCone.TexturePath = IconAssetPath(TEXT("ViewCone"));
		ViewCone.Anchors = FAnchors(1.0f, 0.0f);
		ViewCone.Alignment = FVector2D(0.5f, 0.5f);
		ViewCone.Size = FVector2D(150.0, 150.0);
		ViewCone.Color = FLinearColor(1.0f, 1.0f, 1.0f, 0.4f);
		Spec.Elements.Add(ViewCone);

		// Key hints under the minimap, small (playtest 7): C peeks (shown by Lua only over a grate), F switches the view.
		// H shows or hides them
		FModWidgetElement Hints;
		Hints.Name = TEXT("Hints");
		Hints.Kind = EModWidgetKind::Row;
		Hints.Anchors = FAnchors(1.0f, 0.0f);
		Hints.Alignment = FVector2D(1.0f, 0.0f);
		Hints.Gap = 14.0f;
		Hints.Children = {
			MakeKeyHint(TEXT("PeekHint"), TEXT("Peek"), Hint),
			MakeKeyHint(TEXT("ViewHint"), TEXT("camera"), Hint),
		};
		Spec.Elements.Add(Hints);

		// The vent time: the vent icon and a bar, shown by Lua only while the time isn't full
		FModWidgetElement VentTimeIcon;
		VentTimeIcon.Name = TEXT("VentTimeIcon");
		VentTimeIcon.Kind = EModWidgetKind::Image;
		VentTimeIcon.TexturePath = IconAssetPath(TEXT("Vent"));
		VentTimeIcon.Size = FVector2D(28.0, 28.0);

		FModWidgetElement VentTime;
		VentTime.Name = TEXT("VentTime");
		VentTime.Kind = EModWidgetKind::Row;
		VentTime.Anchors = FAnchors(0.5f, 0.0f);
		VentTime.Alignment = FVector2D(0.5f, 0.0f);
		VentTime.Position = FVector2D(0.0, 32.0);
		VentTime.Gap = 10.0f;
		VentTime.bHidden = true;
		VentTime.Children = {VentTimeIcon, MakeBar(TEXT("VentTimeBar"), FVector2D(320.0, 8.0), Cooldown)};
		Spec.Elements.Add(VentTime);

		const FAnchors BottomCentre(0.5f, 1.0f);
		const FVector2D SitOnEdge(0.5f, 1.0f);
		Spec.Elements.Add(MakeText(TEXT("FrenzyText"), BottomCentre, SitOnEdge, FVector2D(0.0, -150.0), 26, Frenzy,
			TEXT("")));
		Spec.Elements.Add(MakeText(TEXT("StatusText"), BottomCentre, SitOnEdge, FVector2D(0.0, -110.0), 22,
			FLinearColor::White, TEXT("")));

		// Above the centre: a word in huge red letters at the moments that matter most, which Lua fades out ("RUN" as
		// the entity's fleeing phase starts)
		Spec.Elements.Add(MakeText(TEXT("BannerText"), FAnchors(0.5f, 0.5f), FVector2D(0.5f, 0.5f),
			FVector2D(0.0, -200.0), 150, Frenzy, TEXT("")));

		// Bottom right (playtest 8): how many respawns the crew has left, which Lua keeps up to date. The entity wins
		// when the crew is all dead with none left
		Spec.Elements.Add(MakeText(TEXT("RespawnsText"), FAnchors(1.0f, 1.0f), FVector2D(1.0f, 1.0f),
			FVector2D(-56.0, -48.0), 20, Hint, TEXT("")));

		// The pings: a pulse ring each (playtest 9: plain squares read as placeholders), which Lua tints by kind and
		// scales. Positioned in screen pixels from the top-left corner, so they anchor there
		for (int32 PingIndex = 0; PingIndex < PingMarkerCount; ++PingIndex) {
			FModWidgetElement Ping;
			Ping.Name = FName(*FString::Printf(TEXT("Ping%d"), PingIndex));
			Ping.Kind = EModWidgetKind::Image;
			Ping.TexturePath = IconAssetPath(TEXT("PulseRing"));
			Ping.Anchors = FAnchors(0.0f, 0.0f);
			Ping.Alignment = FVector2D(0.5f, 0.5f);
			Ping.Size = FVector2D(20.0, 20.0);
			Ping.bHidden = true;
			Spec.Elements.Add(Ping);
		}
		return Spec;
	}

	// ////////////////////// //
	//    The host's picker   //
	// ////////////////////// //

	// The picker's tiles: dark like the crew HUD's tracks, lightening under the mouse; Lua tints the chosen one
	const FLinearColor TileColor(0.063f, 0.102f, 0.12f, 0.88f);
	const FVector2D TileSize(164.0, 0.0);
	const FVector2D TileImageSize(96.0, 96.0);

	// One clickable tile: an icon over a label, inside the button Lua polls. Lua reaches the parts as <Name>,
	// <Name>Image and <Name>Label.
	FModWidgetElement MakeTile(const TCHAR* Name, const TCHAR* IconName, const TCHAR* Label) {
		FModWidgetElement Image;
		Image.Name = FName(FString(Name) + TEXT("Image"));
		Image.Kind = EModWidgetKind::Image;
		Image.TexturePath = IconAssetPath(IconName);
		Image.Size = TileImageSize;

		FModWidgetElement Tile;
		Tile.Name = Name;
		Tile.Kind = EModWidgetKind::Button;
		Tile.Color = TileColor;
		Tile.Size = TileSize;
		Tile.Children = {Image, MakeLabel(*(FString(Name) + TEXT("Label")), Label, 16, FLinearColor::White)};
		return Tile;
	}

	// WBP_PickerTile: one tile on its own, which Lua creates for each playable entity (its codex portrait in place of
	// the icon) and each player in the lobby, and adds to the picker's rows.
	FModWidgetSpec MakePickerTileSpec() {
		FModWidgetSpec Spec;
		Spec.AssetPath = TEXT("/Game/Mods/ControllableEntity/WBP_PickerTile");
		Spec.bSingleElementRoot = true;
		Spec.Elements = {MakeTile(TEXT("Tile"), TEXT("Player"), TEXT(""))};
		return Spec;
	}

	// WBP_EntityPicker: the host's picker (playtest 8), opened with F9 in the lobby. Two rows of tiles on a dark
	// panel: the entity (Random, each playable entity, AI only) and the player who plays it (Random, each player,
	// scrolling when the lobby is large). Lua fills the rows and marks the choices.
	FModWidgetSpec MakeEntityPickerSpec() {
		const FAnchors Centre(0.5f, 0.5f);
		const FVector2D Middle(0.5f, 0.5f);

		FModWidgetSpec Spec;
		Spec.AssetPath = TEXT("/Game/Mods/ControllableEntity/WBP_EntityPicker");

		FModWidgetElement Backdrop;
		Backdrop.Name = TEXT("Backdrop");
		Backdrop.Kind = EModWidgetKind::Box;
		Backdrop.Color = FLinearColor(0.02f, 0.03f, 0.035f, 0.92f);
		Backdrop.Size = FVector2D(1080.0, 680.0);
		Spec.Elements.Add(Backdrop);

		Spec.Elements.Add(MakeText(TEXT("EntityHeading"), Centre, Middle, FVector2D(0.0, -290.0), 22,
			FLinearColor::White, TEXT("Entity")));

		FModWidgetElement EntityTiles;
		EntityTiles.Name = TEXT("EntityTiles");
		EntityTiles.Kind = EModWidgetKind::Wrap;
		EntityTiles.Gap = 12.0f;

		FModWidgetElement EntityRow;
		EntityRow.Name = TEXT("EntityRow");
		EntityRow.Kind = EModWidgetKind::Row;
		EntityRow.Position = FVector2D(0.0, -160.0);
		EntityRow.Gap = 12.0f;
		EntityRow.Children = {
			MakeTile(TEXT("RandomEntity"), TEXT("Random"), TEXT("Random")),
			EntityTiles,
			MakeTile(TEXT("AiOnly"), TEXT("AiOnly"), TEXT("AI only")),
		};
		Spec.Elements.Add(EntityRow);

		Spec.Elements.Add(MakeText(TEXT("PlayerHeading"), Centre, Middle, FVector2D(0.0, -20.0), 22,
			FLinearColor::White, TEXT("Player")));

		FModWidgetElement PlayerTiles;
		PlayerTiles.Name = TEXT("PlayerTiles");
		PlayerTiles.Kind = EModWidgetKind::Wrap;
		PlayerTiles.Size = FVector2D(856.0, 0.0);
		PlayerTiles.Gap = 12.0f;

		FModWidgetElement PlayerScroll;
		PlayerScroll.Name = TEXT("PlayerScroll");
		PlayerScroll.Kind = EModWidgetKind::Scroll;
		PlayerScroll.Size = FVector2D(870.0, 250.0);
		PlayerScroll.Children = {PlayerTiles};

		FModWidgetElement PlayerRow;
		PlayerRow.Name = TEXT("PlayerRow");
		PlayerRow.Kind = EModWidgetKind::Row;
		PlayerRow.Position = FVector2D(0.0, 130.0);
		PlayerRow.Gap = 12.0f;
		PlayerRow.Children = {MakeTile(TEXT("RandomPlayer"), TEXT("Random"), TEXT("Random")), PlayerScroll};
		Spec.Elements.Add(PlayerRow);

		Spec.Elements.Add(MakeText(TEXT("CloseHint"), Centre, Middle, FVector2D(0.0, 305.0), 14,
			FLinearColor(0.82f, 0.86f, 0.88f), TEXT("F9 closes")));
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
	// The tile first: the picker's Lua creates tiles of its class
	if (!FBlueprintAssetBuilder::BuildWidget(MakePickerTileSpec())) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Controllable Entity: WBP_PickerTile failed to build"));
		return false;
	}
	if (!FBlueprintAssetBuilder::BuildWidget(MakeEntityPickerSpec())) {
		UE_LOG(LogSpeciesUnknownModKit, Error, TEXT("Controllable Entity: WBP_EntityPicker failed to build"));
		return false;
	}

	UE_LOG(LogSpeciesUnknownModKit, Display, TEXT("Controllable Entity assets built"));
	return true;
}
