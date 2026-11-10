// Copyright © 2026 Jalapeno Labs

#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "ModAssetBuildLibrary.generated.h"

// Entry points for building each mod's generated assets. Blueprint-callable so editor Python can run them:
// `unreal.ModAssetBuildLibrary.build_controllable_entity_assets()` (see Scripts/build_mod_assets.py).
UCLASS()
class SPECIESUNKNOWNMODKIT_API UModAssetBuildLibrary : public UBlueprintFunctionLibrary {
	GENERATED_BODY()

public:
	// Builds every asset of the Controllable Entity mod under /Game/Mods/ControllableEntity. Returns false after
	// logging the first failure.
	UFUNCTION(BlueprintCallable, Category = "Species Unknown Mods")
	static bool BuildControllableEntityAssets();
};
