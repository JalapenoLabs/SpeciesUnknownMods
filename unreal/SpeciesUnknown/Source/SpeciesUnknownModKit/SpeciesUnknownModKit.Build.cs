// Copyright © 2026 Jalapeno Labs

using UnrealBuildTool;

// Editor-only tooling that generates the mods' Blueprint assets from code, so the assets stay reproducible and
// their definitions stay diffable. Pak mods cannot ship C++, so none of this reaches the game.
public class SpeciesUnknownModKit : ModuleRules {
	public SpeciesUnknownModKit(ReadOnlyTargetRules Target) : base(Target) {
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[] {
			"Core",
			"CoreUObject",
			"Engine",
		});

		PrivateDependencyModuleNames.AddRange(new string[] {
			"AssetRegistry",
			"AssetTools",
			"BlueprintGraph",
			"EditorScriptingUtilities",
			"ImageCore",
			"Kismet",
			"KismetCompiler",
			"Slate",
			"SlateCore",
			"UMG",
			"UMGEditor",
			"UnrealEd",
		});
	}
}
