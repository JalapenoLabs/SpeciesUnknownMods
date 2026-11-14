// Copyright © 2026 Jalapeno Labs

#pragma once

#include "CoreMinimal.h"
#include "EdGraph/EdGraphPin.h"
#include "Engine/EngineTypes.h"
#include "Types/SlateEnums.h"
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
	// One of the mod's textures (FModWidgetElement::TexturePath), drawn at the element's size.
	Image,
	// A key label in a rounded white box, the way the game shows its own key prompts. The label is the variable
	// `<Name>Text`.
	KeyCap,
	// Its children, left to right, centred vertically and `Gap` pixels apart.
	Row,
	// Its children, top to bottom, left-aligned and `Gap` pixels apart.
	Column,
	// A clickable tile: its children top to bottom, centred, on a rounded background in the element's colour that
	// lightens under the mouse and while pressed. Lua polls it (IsHovered, IsPressed) and tints it to mark a choice.
	Button,
	// Its children (and any Lua adds at runtime) left to right, wrapping onto new lines at the element's width,
	// `Gap` pixels apart both ways.
	Wrap,
	// Its children top to bottom, scrolling when they're taller than the element.
	Scroll,
};

// One widget on the widget's canvas, or inside a row. Every element becomes a variable on the generated class under
// its name, so Lua reaches it as `hud.<Name>`.
struct FModWidgetElement {
	FName Name;
	EModWidgetKind Kind = EModWidgetKind::Text;
	// Where on screen the element is pinned (0..1 per axis), and which point of the element sits there. Only for
	// elements on the canvas; a row places its children itself. Anchors that span an area (FAnchors(0, 0, 1, 1): the
	// whole screen) stretch the element over exactly that area, ignoring Position and Size.
	FAnchors Anchors = FAnchors(0.5f, 0.5f);
	FVector2D Alignment = FVector2D(0.5f, 0.5f);
	// Offset from the anchor, in pixels.
	FVector2D Position = FVector2D::ZeroVector;
	// Fixed size in pixels; leave zero to size the element to its content. Inside a row, a fixed size holds its space
	// even while the element is hidden, so the row never shifts. Inside a row or column, an axis left at zero sizes to
	// the content on that axis only.
	FVector2D Size = FVector2D::ZeroVector;
	// Inside a row or column, where an element with a fixed size sits in that space: filling it, or at its own size
	// against one side (centred top to bottom), as a key glyph that Lua sizes to its texture does.
	EHorizontalAlignment ContentAlignment = HAlign_Fill;
	FLinearColor Color = FLinearColor::White;
	FString Text;
	int32 FontSize = 18;
	bool bHidden = false;
	// Image: the long package path of a texture built from an FModTextureSpec, or empty for an image Lua fills (with
	// one of the game's own textures) at runtime.
	FString TexturePath;
	// Row, Column, Button, Wrap and Scroll: the elements they hold, and (Row, Column, Wrap) the space between them.
	TArray<FModWidgetElement> Children;
	float Gap = 0.0f;
};

// A user widget Blueprint: a canvas of elements, or a single element as its root (a tile Lua creates and places in a
// row, which must size to its content). Lua owns all of its behaviour.
struct FModWidgetSpec {
	FString AssetPath;
	TArray<FModWidgetElement> Elements;
	bool bSingleElementRoot = false;
};

// ////////////////////// //
//        Textures        //
// ////////////////////// //

// A UI texture imported from a PNG. The PNGs are rendered from the mod's SVG sources by scripts/build-mod-assets.sh,
// so the SVGs stay the only source of truth.
struct FModTextureSpec {
	// Absolute path of the PNG to import.
	FString SourceFile;
	// Long package path, e.g. "/Game/Mods/ControllableEntity/Icons/T_Icon_Lash".
	FString AssetPath;
};
