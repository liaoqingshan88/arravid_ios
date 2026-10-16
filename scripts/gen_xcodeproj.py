#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 ArrAvid.xcodeproj/project.pbxproj（经典 objectVersion 格式，Xcode 14+ 可直接打开）。

它扫描 ArrAvid/ 目录：
  - 所有 *.swift 加入「编译源」
  - Assets.xcassets / alarm.wav / PrivacyInfo.xcprivacy 加入「资源」
  - Info.plist / ArrAvid.entitlements 由构建配置引用

在 Linux 上运行，目的是产出 Xcode 能直接打开、且 CI 里 xcodebuild 能直接编译的工程；
用脚本生成能保证 UUID 唯一、section 齐全、引用一致。

用法：python3 scripts/gen_xcodeproj.py
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "ArrAvid")
PROJ_DIR = os.path.join(ROOT, "ArrAvid.xcodeproj")

TARGET_NAME = "ArrAvid"
PRODUCT_NAME = "ArrAvid"

RESOURCES = [
    "Resources/Assets.xcassets",
    "Resources/alarm.wav",
    "Resources/PrivacyInfo.xcprivacy",
]

_id_counter = 0

def uid():
    global _id_counter
    _id_counter += 1
    return "%024X" % _id_counter


def scan_sources():
    files = []
    for dirpath, _dirs, filenames in os.walk(SRC_DIR):
        for fn in sorted(filenames):
            if fn.endswith(".swift"):
                files.append(os.path.join(dirpath, fn))
    return files


def file_ref_source(rel):
    return [
        'lastKnownFileType = sourcecode.swift;',
        'name = %s;' % os.path.basename(rel),
        'path = %s;' % rel,
        'sourceTree = "<group>";',
    ]

def file_ref_resource(rel):
    basename = os.path.basename(rel)
    if rel.endswith(".xcassets"):
        ftype = "folder.assetcatalog"
    elif rel.endswith(".wav"):
        ftype = "audio.wav"
    elif rel.endswith(".xcprivacy"):
        ftype = "text.xml"
    else:
        ftype = "file"
    return [
        'lastKnownFileType = %s;' % ftype,
        'name = %s;' % basename,
        'path = %s;' % rel,
        'sourceTree = "<group>";',
    ]

def file_ref_plist(rel):
    ftype = "text.plist.entitlements" if rel.endswith(".entitlements") else "text.plist.xml"
    return [
        'lastKnownFileType = %s;' % ftype,
        'name = %s;' % os.path.basename(rel),
        'path = %s;' % rel,
        'sourceTree = "<group>";',
    ]


def project_config(name, buildtype):
    shared = [
        'ALWAYS_SEARCH_USER_PATHS = NO;',
        'CLANG_ANALYZER_NONNULL = YES;',
        'CLANG_ENABLE_MODULES = YES;',
        'CLANG_ENABLE_OBJC_ARC = YES;',
        'CLANG_ENABLE_OBJC_WEAK = YES;',
        'CLANG_WARN_BOOL_CONVERSION = YES;',
        'CLANG_WARN_CONSTANT_CONVERSION = YES;',
        'CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;',
        'CLANG_WARN_EMPTY_BODY = YES;',
        'CLANG_WARN_ENUM_CONVERSION = YES;',
        'CLANG_WARN_INFINITE_RECURSION = YES;',
        'CLANG_WARN_INT_CONVERSION = YES;',
        'CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;',
        'CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;',
        'CLANG_WARN_UNREACHABLE_CODE = YES;',
        'COPY_PHASE_STRIP = NO;',
        'ENABLE_STRICT_OBJC_MSGSEND = YES;',
        'GCC_C_LANGUAGE_STANDARD = gnu17;',
        'GCC_NO_COMMON_BLOCKS = YES;',
        'GCC_WARN_64_TO_32_BIT_CONVERSION = YES;',
        'GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;',
        'GCC_WARN_UNDECLARED_SELECTOR = YES;',
        'GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;',
        'GCC_WARN_UNUSED_FUNCTION = YES;',
        'GCC_WARN_UNUSED_VARIABLE = YES;',
        'IPHONEOS_DEPLOYMENT_TARGET = 15.0;',
        'SDKROOT = iphoneos;',
    ]
    if buildtype == "debug":
        extra = [
            'DEBUG_INFORMATION_FORMAT = dwarf;',
            'ENABLE_TESTABILITY = YES;',
            'GCC_OPTIMIZATION_LEVEL = 0;',
            'GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");',
            'ONLY_ACTIVE_ARCH = YES;',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;',
            'SWIFT_OPTIMIZATION_LEVEL = "-Onone";',
        ]
    else:
        extra = [
            'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";',
            'ENABLE_NS_ASSERTIONS = NO;',
            'SWIFT_COMPILATION_MODE = wholemodule;',
            'SWIFT_OPTIMIZATION_LEVEL = "-O";',
            'VALIDATE_PRODUCT = YES;',
        ]
    return ['name = %s;' % name] + shared + extra


def target_config(name, buildtype):
    # 同一份基础配置 + 可选 debug/release 差异
    base = [
        'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;',
        'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;',
        'CODE_SIGN_ENTITLEMENTS = ArrAvid/ArrAvid.entitlements;',
        'CODE_SIGN_STYLE = Automatic;',
        'CURRENT_PROJECT_VERSION = 22;',
        'DEVELOPMENT_TEAM = "";',
        'ENABLE_PREVIEWS = YES;',
        'ENABLE_USER_SCRIPT_SANDBOXING = NO;',
        'GENERATE_INFOPLIST_FILE = NO;',
        'INFOPLIST_FILE = ArrAvid/Info.plist;',
        'IPHONEOS_DEPLOYMENT_TARGET = 15.0;',
        'LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");',
        'MARKETING_VERSION = 1.4.3;',
        'PRODUCT_BUNDLE_IDENTIFIER = com.arravid.reminder;',
        'PRODUCT_NAME = "$(TARGET_NAME)";',
        'SWIFT_VERSION = 5.0;',
        'TARGETED_DEVICE_FAMILY = 1;',
    ]
    return ['name = %s;' % name] + base


SCHEME_TEMPLATE = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%(target_id)s"
               BuildableName = "%(product_name)s.app"
               BlueprintName = "%(target_name)s"
               ReferencedContainer = "container:ArrAvid.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(target_id)s"
            BuildableName = "%(product_name)s.app"
            BlueprintName = "%(target_name)s"
            ReferencedContainer = "container:ArrAvid.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(target_id)s"
            BuildableName = "%(product_name)s.app"
            BlueprintName = "%(target_name)s"
            ReferencedContainer = "container:ArrAvid.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''


def main():
    src_files = scan_sources()
    objects = []

    def add(oid, isa, body):
        objects.append((oid, isa, body))

    # ── 文件引用 ──
    source_refs = []
    for f in src_files:
        rel = os.path.relpath(f, SRC_DIR).replace(os.sep, "/")
        oid = uid()
        source_refs.append((oid, rel))
        add(oid, "PBXFileReference", file_ref_source(rel))

    res_refs = []
    for r in RESOURCES:
        oid = uid()
        res_refs.append((oid, r))
        add(oid, "PBXFileReference", file_ref_resource(r))

    info_ref = uid()
    add(info_ref, "PBXFileReference", file_ref_plist("Info.plist"))
    ent_ref = uid()
    add(ent_ref, "PBXFileReference", file_ref_plist("ArrAvid.entitlements"))
    product_ref = uid()
    add(product_ref, "PBXFileReference", [
        'explicitFileType = wrapper.application;',
        'includeInIndex = 0;',
        'path = %s.app;' % PRODUCT_NAME,
        'sourceTree = BUILT_PRODUCTS_DIR;',
    ])

    # ── Build Files ──
    src_build = []
    for oid, rel in source_refs:
        bid = uid()
        src_build.append((bid, os.path.basename(rel)))
        add(bid, "PBXBuildFile", ['fileRef = %s;' % oid])
    res_build = []
    for oid, rel in res_refs:
        bid = uid()
        res_build.append((bid, os.path.basename(rel)))
        add(bid, "PBXBuildFile", ['fileRef = %s;' % oid])

    # ── Groups ──
    grouped = {}
    for f in src_files:
        rel = os.path.relpath(f, SRC_DIR).replace(os.sep, "/")
        g = os.path.dirname(rel)
        grouped.setdefault(g, []).append(f)

    sub_group_ids = {}
    for g in sorted(grouped.keys()):
        if g == "":
            continue
        gid = uid()
        sub_group_ids[g] = gid
        children = []
        for f in grouped[g]:
            rel = os.path.relpath(f, SRC_DIR).replace(os.sep, "/")
            for oid, r2 in source_refs:
                if r2 == rel:
                    children.append('%s /* %s */' % (oid, os.path.basename(rel)))
                    break
        add(gid, "PBXGroup", [
            'children = (%s);' % ", ".join(children),
            'name = %s;' % (g.split("/")[-1]),
            'path = %s;' % g,
            'sourceTree = "<group>";',
        ])

    arr_group = uid()
    arr_children = []
    for g in sorted(grouped.keys()):
        if g:
            arr_children.append('%s /* %s */' % (sub_group_ids[g], g.split("/")[-1]))
    for f in grouped.get("", []):
        rel = os.path.relpath(f, SRC_DIR).replace(os.sep, "/")
        for oid, r2 in source_refs:
            if r2 == rel:
                arr_children.append('%s /* %s */' % (oid, os.path.basename(rel)))
                break
    for oid, rel in res_refs:
        arr_children.append('%s /* %s */' % (oid, os.path.basename(rel)))
    arr_children.append('%s /* Info.plist */' % info_ref)
    arr_children.append('%s /* ArrAvid.entitlements */' % ent_ref)
    add(arr_group, "PBXGroup", [
        'children = (%s);' % ", ".join(arr_children),
        'path = ArrAvid;',
        'sourceTree = "<group>";',
    ])

    products_group = uid()
    add(products_group, "PBXGroup", [
        'children = (%s /* %s.app */);' % (product_ref, PRODUCT_NAME),
        'name = Products;',
        'sourceTree = "<group>";',
    ])
    main_group = uid()
    add(main_group, "PBXGroup", [
        'children = (%s /* ArrAvid */, %s /* Products */);' % (arr_group, products_group),
        'sourceTree = "<group>";',
    ])

    # ── Build Phases ──
    sources_phase = uid()
    add(sources_phase, "PBXSourcesBuildPhase", [
        'buildActionMask = 2147483647;',
        'files = (%s);' % ", ".join('%s /* %s */' % (bid, name) for bid, name in src_build),
        'runOnlyForDeploymentPostprocessing = 0;',
    ])
    resources_phase = uid()
    add(resources_phase, "PBXResourcesBuildPhase", [
        'buildActionMask = 2147483647;',
        'files = (%s);' % ", ".join('%s /* %s */' % (bid, name) for bid, name in res_build),
        'runOnlyForDeploymentPostprocessing = 0;',
    ])
    frameworks_phase = uid()
    add(frameworks_phase, "PBXFrameworksBuildPhase", [
        'buildActionMask = 2147483647;',
        'files = ();',
        'runOnlyForDeploymentPostprocessing = 0;',
    ])

    # ── 配置列表 ──
    proj_debug = uid()
    proj_release = uid()
    proj_list = uid()
    add(proj_list, "XCConfigurationList", [
        'buildConfigurations = (%s, %s);' % (proj_debug, proj_release),
        'defaultConfigurationIsVisible = 0;',
        'defaultConfigurationName = Release;',
    ])
    tgt_debug = uid()
    tgt_release = uid()
    tgt_list = uid()
    add(tgt_list, "XCConfigurationList", [
        'buildConfigurations = (%s, %s);' % (tgt_debug, tgt_release),
        'defaultConfigurationIsVisible = 0;',
        'defaultConfigurationName = Release;',
    ])

    # ── Target ──
    target = uid()
    add(target, "PBXNativeTarget", [
        'buildConfigurationList = %s;' % tgt_list,
        'buildPhases = (%s, %s, %s);' % (sources_phase, frameworks_phase, resources_phase),
        'buildRules = ();',
        'dependencies = ();',
        'name = %s;' % TARGET_NAME,
        'productName = %s;' % TARGET_NAME,
        'productReference = %s /* %s.app */;' % (product_ref, PRODUCT_NAME),
        'productType = "com.apple.product-type.application";',
    ])

    # ── Project ──
    project = uid()
    add(project, "PBXProject", [
        'attributes = {',
        '\tBuildIndependentTargetsInParallel = 1;',
        '\tLastSwiftUpdateCheck = 1500;',
        '\tLastUpgradeCheck = 1500;',
        '\tTargetAttributes = {',
        '\t\t%s = { CreatedOnToolsVersion = 15.0; };' % target,
        '\t};',
        '};',
        'buildConfigurationList = %s;' % proj_list,
        'compatibilityVersion = "Xcode 14.0";',
        'developmentRegion = zh_CN;',
        'hasScannedForEncodings = 0;',
        'knownRegions = (zh-Hans, en, Base);',
        'mainGroup = %s;' % main_group,
        'productRefGroup = %s /* Products */;' % products_group,
        'projectDirPath = "";',
        'projectRoot = "";',
        'targets = (%s /* %s */);' % (target, TARGET_NAME),
    ])

    # ── 构建配置 ──
    add(proj_debug, "XCBuildConfiguration", project_config("Debug", "debug"))
    add(proj_release, "XCBuildConfiguration", project_config("Release", "release"))
    add(tgt_debug, "XCBuildConfiguration", target_config("Debug", "debug"))
    add(tgt_release, "XCBuildConfiguration", target_config("Release", "release"))

    # ── 渲染到文件 ──
    lines = ['// !$*UTF8*$!', '{']
    for oid, isa, body in objects:
        lines.append('\t\t%s /* %s */ = {' % (oid, isa))
        lines.append('\t\t\tisa = %s;' % isa)
        for b in body:
            lines.append('\t\t\t' + b)
        lines.append('\t\t};')
    lines.append('\trootObject = %s /* Project object */;' % project)
    lines.append('}')
    lines.append('')

    os.makedirs(PROJ_DIR, exist_ok=True)
    out = os.path.join(PROJ_DIR, 'project.pbxproj')
    with open(out, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    ws_dir = os.path.join(PROJ_DIR, 'project.xcworkspace')
    os.makedirs(ws_dir, exist_ok=True)
    with open(os.path.join(ws_dir, 'contents.xcworkspacedata'), 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<Workspace version = "1.0">\n'
                '   <FileRef location = "self:">\n   </FileRef>\n'
                '</Workspace>\n')

    # 共享 Scheme（CI 用 xcodebuild -scheme ArrAvid 能直接构建；Xcode 打开也直接可用）
    scheme_dir = os.path.join(PROJ_DIR, 'xcshareddata', 'xcschemes')
    os.makedirs(scheme_dir, exist_ok=True)
    scheme = SCHEME_TEMPLATE % {
        'target_id': target,
        'product_name': PRODUCT_NAME,
        'target_name': TARGET_NAME,
    }
    with open(os.path.join(scheme_dir, '%s.xcscheme' % TARGET_NAME), 'w', encoding='utf-8') as f:
        f.write(scheme)

    print('generated %s' % out)
    print('  scheme: %s.xcscheme' % TARGET_NAME)
    print('  swift sources: %d' % len(src_files))
    for f in src_files:
        print('    -', os.path.relpath(f, SRC_DIR))
    print('  resources: %d' % len(RESOURCES))
    for r in RESOURCES:
        print('    -', r)


if __name__ == '__main__':
    main()