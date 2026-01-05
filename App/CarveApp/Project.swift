import ProjectDescription
import CarveEnvironment

let projectName = "CarveApp"

let dependencies: [TargetDependency] = [
    .CarveFeature,
    .SettingsFeature,
    .FirebaseAnalytics,
    .FirebaseMessaging,
    
    .TCAArchitecture
]

let script: [TargetScript] = [.swiftLint, .firebaseCrashlytics]

let settings: Settings = .settings(
    base: SettingsDictionary()
        .automaticCodeSigning(devTeam: "H4MSW7FUBB")
        .otherLinkerFlags(["-all_load -Objc"])
        .debugInformationFormat(.dwarfWithDsym)
        .marketingVersion("1.2.2")
        .currentProjectVersion("1")
        .merging([
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS": "YES",
            "FEEDBACK_ADDRESS": "retake_joy@naver.com",
            "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
            "CLOUDKIT_CONTAINER_ID": "iCloud.Carve.SwiftData.iCloud"
        ]),
    configurations: [
        .debug(name: "Debug", settings: [
            "CLOUDKIT_CONTAINER_ID": "iCloud.Carve.SwiftData.iCloud.dev"
        ]),
        .release(name: "Release", settings: [
            "CLOUDKIT_CONTAINER_ID": "iCloud.Carve.SwiftData.iCloud"
        ])
    ]
)

let targets: [Target] = [
    .makeAppTarget(
        name: projectName,
        entitlements: .file(path: .relativeToCurrentFile("Support/Carve.entitlements")),
        scripts: script,
        dependencies: dependencies,
        launchArguments: [
            .launchArgument(name: "-FIRDebugEnabled", isEnabled: true)
        ]
    )
]


let project = Project.makeModule(
    name: projectName,
    targets: targets,
    settings: settings
)
