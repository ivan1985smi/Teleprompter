#!/usr/bin/env python3
"""Generate Teleprompter.xcodeproj without third-party dependencies.

The project uses classic PBX groups (Xcode 14+/objectVersion 56), so it opens
in modern Xcode and does not require Xcode 16 synchronized folders.
Run from the repository root: python3 Tools/generate_project.py
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Teleprompter"
PROJECT = ROOT / "Teleprompter.xcodeproj"

def uid(name: str) -> str:
    return hashlib.md5(("Teleprompter:" + name).encode()).hexdigest()[:24].upper()

def fmt(value) -> str:
    if isinstance(value, list):
        if not value:
            return "()"
        return "(\n" + "".join(f"\t\t\t\t{fmt(v)},\n" for v in value) + "\t\t\t)"
    if isinstance(value, bool):
        return "YES" if value else "NO"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        if re.fullmatch(r"[A-F0-9]{24} /\* [^*]+ \*/", value):
            return value
        if re.fullmatch(r"[A-Za-z0-9_]+", value):
            return value
        escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return f'"{escaped}"'
    raise TypeError(value)

names: dict[str, str] = {}
objects: dict[str, list[str]] = {}

def ref(obj_id: str) -> str:
    return f"{obj_id} /* {names.get(obj_id, '')} */"

def add(isa: str, key: str, name: str, fields: dict[str, object]) -> str:
    obj_id = uid(key)
    names[obj_id] = name
    lines = [f"\t\t{obj_id} /* {name} */ = {{", f"\t\t\tisa = {isa};"]
    for k, v in fields.items():
        if isinstance(v, str) and v.startswith("RAW:"):
            rendered = v[4:]
        else:
            rendered = fmt(v)
        # Multiline lists/dicts need indentation-friendly rendering.
        if "\n" in rendered:
            rendered = rendered.replace("\n", "\n\t")
        lines.append(f"\t\t\t{k} = {rendered};")
    lines.append("\t\t};")
    objects.setdefault(isa, []).append("\n".join(lines))
    return obj_id

# File references and groups -------------------------------------------------
product_id = add("PBXFileReference", "product", "Teleprompter.app", {
    "explicitFileType": "wrapper.application",
    "includeInIndex": 0,
    "path": "Teleprompter.app",
    "sourceTree": "BUILT_PRODUCTS_DIR",
})
framework_id = add("PBXFileReference", "framework-gamecontroller", "GameController.framework", {
    "lastKnownFileType": "wrapper.framework",
    "name": "GameController.framework",
    "path": "System/Library/Frameworks/GameController.framework",
    "sourceTree": "SDKROOT",
})
info_id = add("PBXFileReference", "file-info-plist", "Info.plist", {
    "lastKnownFileType": "text.plist.xml",
    "path": "Info.plist",
    "sourceTree": "<group>",
})
assets_id = add("PBXFileReference", "file-assets", "Assets.xcassets", {
    "lastKnownFileType": "folder.assetcatalog",
    "path": "Assets.xcassets",
    "sourceTree": "<group>",
})

swift_files = sorted(SOURCE.rglob("*.swift"))
file_ids: dict[Path, str] = {}
for path in swift_files:
    rel = path.relative_to(SOURCE)
    file_ids[path] = add("PBXFileReference", f"file-{rel}", path.name, {
        "lastKnownFileType": "sourcecode.swift",
        "path": path.name,
        "sourceTree": "<group>",
    })

# Groups mirror folders.
group_children: dict[str, list[str]] = {
    "App": [], "Models": [], "Services": [], "ViewModels": [], "Views": [], "Resources": [ref(assets_id)],
}
for path in swift_files:
    rel = path.relative_to(SOURCE)
    group_children[str(rel.parent)].append(ref(file_ids[path]))

group_ids: dict[str, str] = {}
for group, children in group_children.items():
    group_ids[group] = add("PBXGroup", f"group-{group}", group, {
        "children": children,
        "path": group,
        "sourceTree": "<group>",
    })

teleprompter_children = [ref(group_ids[g]) for g in ["App", "Models", "Services", "ViewModels", "Views", "Resources"]]
teleprompter_children.append(ref(info_id))
teleprompter_group = add("PBXGroup", "group-Teleprompter", "Teleprompter", {
    "children": teleprompter_children,
    "path": "Teleprompter",
    "sourceTree": "<group>",
})
products_group = add("PBXGroup", "group-Products", "Products", {
    "children": [ref(product_id)],
    "name": "Products",
    "sourceTree": "<group>",
})
frameworks_group = add("PBXGroup", "group-Frameworks", "Frameworks", {
    "children": [ref(framework_id)],
    "name": "Frameworks",
    "sourceTree": "<group>",
})
main_group = add("PBXGroup", "group-main", "", {
    "children": [ref(teleprompter_group), ref(frameworks_group), ref(products_group)],
    "sourceTree": "<group>",
})

# Build files/phases ---------------------------------------------------------
source_build_ids = []
for path in swift_files:
    source_build_ids.append(ref(add("PBXBuildFile", f"build-{path.relative_to(SOURCE)}", path.name + " in Sources", {
        "fileRef": ref(file_ids[path]),
    })))
assets_build_id = ref(add("PBXBuildFile", "build-assets", "Assets.xcassets in Resources", {
    "fileRef": ref(assets_id),
}))
framework_build_id = ref(add("PBXBuildFile", "build-gamecontroller", "GameController.framework in Frameworks", {
    "fileRef": ref(framework_id),
}))

sources_phase = add("PBXSourcesBuildPhase", "phase-sources", "Sources", {
    "buildActionMask": 2147483647,
    "files": source_build_ids,
    "runOnlyForDeploymentPostprocessing": 0,
})
frameworks_phase = add("PBXFrameworksBuildPhase", "phase-frameworks", "Frameworks", {
    "buildActionMask": 2147483647,
    "files": [framework_build_id],
    "runOnlyForDeploymentPostprocessing": 0,
})
resources_phase = add("PBXResourcesBuildPhase", "phase-resources", "Resources", {
    "buildActionMask": 2147483647,
    "files": [assets_build_id],
    "runOnlyForDeploymentPostprocessing": 0,
})

# Build configurations -------------------------------------------------------
project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "CURRENT_PROJECT_VERSION": 1,
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
    "MARKETING_VERSION": "1.0",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}
project_debug = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": 0,
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
project_release = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "ONLY_ACTIVE_ARCH": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
})

def settings_dict(settings: dict[str, object]) -> str:
    lines = ["{"]
    for key in sorted(settings):
        value = fmt(settings[key])
        if "\n" in value:
            value = value.replace("\n", "\n\t\t\t\t")
        lines.append(f"\t\t\t\t{key} = {value};")
    lines.append("\t\t\t}")
    return "RAW:" + "\n".join(lines)

project_debug_id = add("XCBuildConfiguration", "config-project-debug", "Debug", {
    "buildSettings": settings_dict(project_debug),
    "name": "Debug",
})
project_release_id = add("XCBuildConfiguration", "config-project-release", "Release", {
    "buildSettings": settings_dict(project_release),
    "name": "Release",
})
project_config_list = add("XCConfigurationList", "configlist-project", "Build configuration list for PBXProject Teleprompter", {
    "buildConfigurations": [ref(project_debug_id), ref(project_release_id)],
    "defaultConfigurationIsVisible": 0,
    "defaultConfigurationName": "Release",
})

target_common = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "DEVELOPMENT_TEAM": "",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Teleprompter/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "ru.teleprompter.app",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SUPPORTS_MACCATALYST": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_STRICT_CONCURRENCY": "targeted",
    "TARGETED_DEVICE_FAMILY": 1,
}
target_debug_id = add("XCBuildConfiguration", "config-target-debug", "Debug", {
    "buildSettings": settings_dict(target_common),
    "name": "Debug",
})
target_release_id = add("XCBuildConfiguration", "config-target-release", "Release", {
    "buildSettings": settings_dict(target_common),
    "name": "Release",
})
target_config_list = add("XCConfigurationList", "configlist-target", "Build configuration list for PBXNativeTarget Teleprompter", {
    "buildConfigurations": [ref(target_debug_id), ref(target_release_id)],
    "defaultConfigurationIsVisible": 0,
    "defaultConfigurationName": "Release",
})

target_id = add("PBXNativeTarget", "target-app", "Teleprompter", {
    "buildConfigurationList": ref(target_config_list),
    "buildPhases": [ref(sources_phase), ref(frameworks_phase), ref(resources_phase)],
    "buildRules": [],
    "dependencies": [],
    "name": "Teleprompter",
    "productName": "Teleprompter",
    "productReference": ref(product_id),
    "productType": "com.apple.product-type.application",
})

attributes = (
    "RAW:{\n"
    "\t\t\t\tBuildIndependentTargetsInParallel = YES;\n"
    "\t\t\t\tLastSwiftUpdateCheck = 1500;\n"
    "\t\t\t\tLastUpgradeCheck = 1500;\n"
    "\t\t\t\tTargetAttributes = {\n"
    f"\t\t\t\t\t{target_id} = {{\n"
    "\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n"
    "\t\t\t\t\t};\n"
    "\t\t\t\t};\n"
    "\t\t\t}"
)
project_id = add("PBXProject", "project", "Project object", {
    "attributes": attributes,
    "buildConfigurationList": ref(project_config_list),
    "compatibilityVersion": "Xcode 14.0",
    "developmentRegion": "ru",
    "hasScannedForEncodings": 0,
    "knownRegions": ["en", "Base", "ru"],
    "mainGroup": ref(main_group),
    "productRefGroup": ref(products_group),
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [ref(target_id)],
})

# Render pbxproj -------------------------------------------------------------
order = [
    "PBXBuildFile", "PBXFileReference", "PBXFrameworksBuildPhase", "PBXGroup",
    "PBXNativeTarget", "PBXProject", "PBXResourcesBuildPhase", "PBXSourcesBuildPhase",
    "XCBuildConfiguration", "XCConfigurationList",
]
out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {", ""]
for isa in order:
    if isa not in objects:
        continue
    out.append(f"/* Begin {isa} section */")
    out.extend(objects[isa])
    out.append(f"/* End {isa} section */")
out.extend(["\t};", f"\trootObject = {ref(project_id)};", "}", ""])

PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / "project.pbxproj").write_text("\n".join(out), encoding="utf-8")

# Shared scheme for xcodebuild / CI -----------------------------------------
scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
buildable = f'''            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "Teleprompter.app"
               BlueprintName = "Teleprompter"
               ReferencedContainer = "container:Teleprompter.xcodeproj">
            </BuildableReference>'''
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
{buildable}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="NO" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
{buildable}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="NO">
      <BuildableProductRunnable runnableDebuggingMode="0">
{buildable}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES">
   </ArchiveAction>
</Scheme>
'''
(scheme_dir / "Teleprompter.xcscheme").write_text(scheme, encoding="utf-8")
print(f"Generated {PROJECT} with target {target_id} and {len(swift_files)} Swift files")
