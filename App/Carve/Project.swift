import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "Carve"

let dependencies: [TargetDependency] = [
    .FeatureCarve,
    .FeatureSettings,
    .FirebaseAnalytics,
    .FirebaseMessaging,
    
    .TCAArchitecture
]

let script: [TargetScript] = [.swiftLint, .firebaseCrashlytics]

let settings: Settings = .settings(
    base: SettingsDictionary()
        .automaticCodeSigning(devTeam: "H4MSW7FUBB")
        .otherLinkerFlags(["-all_load -Objc"])
        .merging([
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS": "YES",
            "FEEDBACK_ADDRESS": "retake_joy@naver.com"
        ])
)

let targets: [Target] = [
    .makeAppTarget(
        name: .configuration(projectName),
        entitlements: .file(path: .relativeToCurrentFile("Support/Carve.entitlements")),
        scripts: script,
        dependencies: dependencies
    )
]


let project = Project.makeModule(
    name: projectName,
    targets: targets,
    settings: settings
)
