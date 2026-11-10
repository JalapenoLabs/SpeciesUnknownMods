// Copyright © 2026 Jalapeno Labs

using UnrealBuildTool;

// The project only ever runs as an editor: it authors and cooks mod content. Nothing here ships to players.
public class SpeciesUnknownEditorTarget : TargetRules {
	public SpeciesUnknownEditorTarget(TargetInfo Target) : base(Target) {
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.V6;
		IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_7;
		ExtraModuleNames.Add("SpeciesUnknownModKit");
	}
}
