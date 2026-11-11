// Copyright © 2026 Jalapeno Labs

#pragma once

#include "CoreMinimal.h"
#include "BlueprintAssetSpec.h"

class UBlueprint;
class UBlueprintGeneratedClass;
class UTexture2D;
class UWidget;
class UWidgetTree;

// Turns asset specs into saved assets. Every build replaces the asset from scratch, so an asset never keeps anything
// its spec doesn't describe.
class SPECIESUNKNOWNMODKIT_API FBlueprintAssetBuilder {
public:
	// Each returns the saved asset, or nullptr after logging why the build failed.
	static UBlueprint* BuildNetworkActor(const FModNetworkActorSpec& Spec);
	static UBlueprint* BuildWidget(const FModWidgetSpec& Spec);
	static UTexture2D* BuildTexture(const FModTextureSpec& Spec);

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

	// Places a top-level element on the canvas; returns false after logging when it can't be built
	static bool AddWidgetElement(class UWidgetBlueprint* WidgetBlueprint, class UCanvasPanel* Canvas,
		const FModWidgetElement& Element);
	// Builds an element and, for rows, everything inside it; nullptr after logging when something is missing
	static UWidget* ConstructElement(UWidgetTree* WidgetTree, const FModWidgetElement& Element);

	static UWidget* ConstructText(UWidgetTree* WidgetTree, const FModWidgetElement& Element);
	static UWidget* ConstructProgressBar(UWidgetTree* WidgetTree, const FModWidgetElement& Element);
	static UWidget* ConstructBox(UWidgetTree* WidgetTree, const FModWidgetElement& Element);
	static UWidget* ConstructImage(UWidgetTree* WidgetTree, const FModWidgetElement& Element);
	static UWidget* ConstructKeyCap(UWidgetTree* WidgetTree, const FModWidgetElement& Element);
	static UWidget* ConstructRow(UWidgetTree* WidgetTree, const FModWidgetElement& Element);
	static UWidget* ConstructColumn(UWidgetTree* WidgetTree, const FModWidgetElement& Element);
	// A row's or column's child, in a size box when it has a fixed size, so its space holds while Lua hides it
	static UWidget* ConstructSizedChild(UWidgetTree* WidgetTree, const FModWidgetElement& Child);

	// ////////////////////// //
	//     Class defaults     //
	// ////////////////////// //

	static bool SetDefaultBool(UObject* DefaultObject, FName PropertyName, bool bValue);
};
