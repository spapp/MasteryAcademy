#!/usr/bin/env python3
"""Writes a minimal Xcode project (objectVersion 77, synchronized folders) for an iOS app,
a Swift Testing unit-test target, and optionally a WidgetKit extension.

Usage: make_project.py <project_dir> <Name> <bundle_prefix> [--widget] [--shared Shared]
The source folders <Name>/, <Name>Tests/ (and <Name>Widget/, Shared/) must already exist.
"""
import sys, os, hashlib

def uid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()

def main():
    root, name, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    widget = "--widget" in sys.argv
    shared = None
    if "--shared" in sys.argv:
        shared = sys.argv[sys.argv.index("--shared") + 1]
    app_plist = "--app-plist" in sys.argv
    entitlements = "--entitlements" in sys.argv
    deployment = "17.0"
    tests = f"{name}Tests"
    wname = f"{name}Widget"
    U = lambda *p: uid(name, *p)

    proj, main_group, products = U("project"), U("maingroup"), U("products")
    app_t, test_t, w_t = U("t", "app"), U("t", "tests"), U("t", "widget")
    app_ref, test_ref, w_ref = U("ref", "app"), U("ref", "tests"), U("ref", "widget")
    g_app, g_tests, g_w, g_shared = U("g", "app"), U("g", "tests"), U("g", "widget"), U("g", "shared")
    ex_w = U("ex", "widget")

    def phases(t):
        return U("src", t), U("fw", t), U("res", t)

    objs = []
    add = objs.append

    # file references for products
    add(f'{app_ref} /* {name}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {name}.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
    add(f'{test_ref} /* {tests}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {tests}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
    if widget:
        add(f'{w_ref} /* {wname}.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = {wname}.appex; sourceTree = BUILT_PRODUCTS_DIR; }};')

    # synchronized groups
    app_excluded = (["Info.plist"] if app_plist else []) + ([f"{name}.entitlements"] if entitlements else [])
    if app_excluded:
        ex_app = U("ex", "app")
        add(f'{ex_app} /* exceptions */ = {{isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = ( {", ".join(app_excluded)}, ); target = {app_t} /* {name} */; }};')
        add(f'{g_app} /* {name} */ = {{isa = PBXFileSystemSynchronizedRootGroup; exceptions = ( {ex_app} /* exceptions */, ); path = {name}; sourceTree = "<group>"; }};')
    else:
        add(f'{g_app} /* {name} */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = {name}; sourceTree = "<group>"; }};')
    add(f'{g_tests} /* {tests} */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = {tests}; sourceTree = "<group>"; }};')
    if widget:
        add(f'{ex_w} /* exceptions */ = {{isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = ( Info.plist{", " + wname + ".entitlements" if entitlements else ""}, ); target = {w_t} /* {wname} */; }};')
        add(f'{g_w} /* {wname} */ = {{isa = PBXFileSystemSynchronizedRootGroup; exceptions = ( {ex_w} /* exceptions */, ); path = {wname}; sourceTree = "<group>"; }};')
    if shared:
        add(f'{g_shared} /* {shared} */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = {shared}; sourceTree = "<group>"; }};')

    children = [g_app, g_tests] + ([g_w] if widget else []) + ([g_shared] if shared else []) + [products]
    add(f'{main_group} = {{isa = PBXGroup; children = ( {", ".join(children)}, ); sourceTree = "<group>"; }};')
    prod_children = [app_ref, test_ref] + ([w_ref] if widget else [])
    add(f'{products} /* Products */ = {{isa = PBXGroup; children = ( {", ".join(prod_children)}, ); name = Products; sourceTree = "<group>"; }};')

    # build phases
    targets = [("app", app_t), ("tests", test_t)] + ([("widget", w_t)] if widget else [])
    for key, _ in targets:
        s, f, r = phases(key)
        add(f'{s} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; }};')
        add(f'{f} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; }};')
        add(f'{r} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ( ); runOnlyForDeploymentPostprocessing = 0; }};')

    embed_phase, embed_file = U("embed"), U("embedfile")
    if widget:
        add(f'{embed_file} /* {wname}.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {w_ref} /* {wname}.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};')
        add(f'{embed_phase} /* Embed Foundation Extensions */ = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ( {embed_file} /* {wname}.appex */, ); name = "Embed Foundation Extensions"; runOnlyForDeploymentPostprocessing = 0; }};')

    # dependencies
    proxy_tests, dep_tests = U("proxy", "tests"), U("dep", "tests")
    add(f'{proxy_tests} /* PBXContainerItemProxy */ = {{isa = PBXContainerItemProxy; containerPortal = {proj} /* Project object */; proxyType = 1; remoteGlobalIDString = {app_t}; remoteInfo = {name}; }};')
    add(f'{dep_tests} /* PBXTargetDependency */ = {{isa = PBXTargetDependency; target = {app_t} /* {name} */; targetProxy = {proxy_tests} /* PBXContainerItemProxy */; }};')
    proxy_w, dep_w = U("proxy", "widget"), U("dep", "widget")
    if widget:
        add(f'{proxy_w} /* PBXContainerItemProxy */ = {{isa = PBXContainerItemProxy; containerPortal = {proj} /* Project object */; proxyType = 1; remoteGlobalIDString = {w_t}; remoteInfo = {wname}; }};')
        add(f'{dep_w} /* PBXTargetDependency */ = {{isa = PBXTargetDependency; target = {w_t} /* {wname} */; targetProxy = {proxy_w} /* PBXContainerItemProxy */; }};')

    # build configurations
    def cfg(key, conf, settings):
        cid = U("cfg", key, conf)
        body = " ".join(f'{k} = {v};' for k, v in settings.items())
        add(f'{cid} /* {conf} */ = {{isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {conf}; }};')
        return cid

    def cfglist(key, ids, owner):
        lid = U("cfglist", key)
        add(f'{lid} /* Build configuration list for {owner} */ = {{isa = XCConfigurationList; buildConfigurations = ( {ids[0]} /* Debug */, {ids[1]} /* Release */, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
        return lid

    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17", "IPHONEOS_DEPLOYMENT_TARGET": deployment, "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    }
    proj_cfgs = [
        cfg("proj", "Debug", {**common, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
                              "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"', "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'}),
        cfg("proj", "Release", {**common, "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"', "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"}),
    ]
    proj_list = cfglist("proj", proj_cfgs, f'PBXProject "{name}"')

    app_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
        "INFOPLIST_KEY_UISupportedInterfaceOrientations": '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
        "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"', "MARKETING_VERSION": "1.0", "INFOPLIST_KEY_CFBundleDisplayName": '"Mastery Academy"',
        "PRODUCT_BUNDLE_IDENTIFIER": f'"{prefix}.{name}"', "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES", "TARGETED_DEVICE_FAMILY": '"1,2"',
    }
    if widget:
        app_settings["INFOPLIST_KEY_NSSupportsLiveActivities"] = "YES"
    if app_plist:
        app_settings["INFOPLIST_FILE"] = f"{name}/Info.plist"
    if entitlements:
        app_settings["CODE_SIGN_ENTITLEMENTS"] = f"{name}/{name}.entitlements"
    app_cfgs = [cfg("app", c, app_settings) for c in ("Debug", "Release")]
    app_list = cfglist("app", app_cfgs, f'PBXNativeTarget "{name}"')

    test_settings = {
        "BUNDLE_LOADER": '"$(TEST_HOST)"', "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES", "MARKETING_VERSION": "1.0", "PRODUCT_BUNDLE_IDENTIFIER": f'"{prefix}.{tests}"',
        "PRODUCT_NAME": '"$(TARGET_NAME)"', "SWIFT_EMIT_LOC_STRINGS": "NO", "TARGETED_DEVICE_FAMILY": '"1,2"',
        "TEST_HOST": f'"$(BUILT_PRODUCTS_DIR)/{name}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{name}"',
    }
    test_cfgs = [cfg("tests", c, test_settings) for c in ("Debug", "Release")]
    test_list = cfglist("tests", test_cfgs, f'PBXNativeTarget "{tests}"')

    if widget:
        w_settings = {
            "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1", "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_FILE": f"{wname}/Info.plist", "INFOPLIST_KEY_CFBundleDisplayName": wname,
            "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
            "MARKETING_VERSION": "1.0", "PRODUCT_BUNDLE_IDENTIFIER": f'"{prefix}.{name}.{wname}"',
            **({"CODE_SIGN_ENTITLEMENTS": f"{wname}/{wname}.entitlements"} if entitlements else {}),
            "PRODUCT_NAME": '"$(TARGET_NAME)"', "SKIP_INSTALL": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES", "TARGETED_DEVICE_FAMILY": '"1,2"',
        }
        w_cfgs = [cfg("widget", c, w_settings) for c in ("Debug", "Release")]
        w_list = cfglist("widget", w_cfgs, f'PBXNativeTarget "{wname}"')

    # targets
    def target(key, tid, tname, ptype, ref, lst, groups, deps=(), extra_phases=()):
        s, f, r = phases(key)
        ph = [f"{s} /* Sources */", f"{f} /* Frameworks */", f"{r} /* Resources */"] + list(extra_phases)
        add(f'{tid} /* {tname} */ = {{isa = PBXNativeTarget; buildConfigurationList = {lst}; buildPhases = ( {", ".join(ph)}, ); '
            f'buildRules = ( ); dependencies = ( {"".join(d + ", " for d in deps)}); fileSystemSynchronizedGroups = ( {", ".join(groups)}, ); '
            f'name = {tname}; productName = {tname}; productReference = {ref}; productType = "{ptype}"; }};')

    app_groups = [g_app] + ([g_shared] if shared else [])
    target("app", app_t, name, "com.apple.product-type.application", app_ref, app_list, app_groups,
           deps=[dep_w] if widget else [], extra_phases=[f"{embed_phase} /* Embed Foundation Extensions */"] if widget else [])
    target("tests", test_t, tests, "com.apple.product-type.bundle.unit-test", test_ref, test_list, [g_tests], deps=[dep_tests])
    if widget:
        target("widget", w_t, wname, "com.apple.product-type.app-extension", w_ref, w_list, [g_w] + ([g_shared] if shared else []))

    tlist = [app_t, test_t] + ([w_t] if widget else [])
    attrs = " ".join(f'{t} = {{CreatedOnToolsVersion = 26.0; }};' for t in tlist)
    add(f'{proj} /* Project object */ = {{isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2600; LastUpgradeCheck = 2600; '
        f'TargetAttributes = {{ {attrs} }}; }}; buildConfigurationList = {proj_list}; developmentRegion = en; hasScannedForEncodings = 0; '
        f'knownRegions = ( en, Base, ); mainGroup = {main_group}; minimizedProjectReferenceProxies = 1; preferredProjectObjectVersion = 77; '
        f'productRefGroup = {products} /* Products */; projectDirPath = ""; projectRoot = ""; targets = ( {", ".join(tlist)}, ); }};')

    pbx = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\t\t" + "\n\t\t".join(objs) + f"\n\t}};\n\trootObject = {proj} /* Project object */;\n}}\n"

    xcodeproj = os.path.join(root, f"{name}.xcodeproj")
    os.makedirs(os.path.join(xcodeproj, "xcshareddata", "xcschemes"), exist_ok=True)
    with open(os.path.join(xcodeproj, "project.pbxproj"), "w") as fh:
        fh.write(pbx)

    def bref(tid, tname, product):
        return (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{tid}" '
                f'BuildableName = "{product}" BlueprintName = "{tname}" ReferencedContainer = "container:{name}.xcodeproj"></BuildableReference>')
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {bref(app_t, name, name + ".app")}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO" parallelizable = "YES">
            {bref(test_t, tests, tests + ".xctest")}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {bref(app_t, name, name + ".app")}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {bref(app_t, name, name + ".app")}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
'''
    with open(os.path.join(xcodeproj, "xcshareddata", "xcschemes", f"{name}.xcscheme"), "w") as fh:
        fh.write(scheme)
    print("wrote", xcodeproj)

if __name__ == "__main__":
    main()
