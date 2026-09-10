import ProjectDescription
import CarveEnvironment

let projectName = "CarveApp"

let dependencies: [TargetDependency] = [
    .CarveFeature,
    .ChartFeature,
    .SettingsFeature,
    .ClientInterfaces,
    .FirebaseAnalytics,
    .FirebaseMessaging,
    .GoogleAds,
    
    .TCAArchitecture
]

let script: [TargetScript] = [.swiftLint, .firebaseCrashlytics]

let settings: Settings = .settings(
    base: SettingsDictionary()
        .automaticCodeSigning(devTeam: "H4MSW7FUBB")
        .otherLinkerFlags(["-all_load -Objc"])
        .debugInformationFormat(.dwarfWithDsym)
        .marketingVersion("1.3.1")
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
            "CLOUDKIT_CONTAINER_ID": "iCloud.Carve.SwiftData.iCloud.dev",
            "ADMOB_NATIVE_CHART_AD_UNIT_ID": "ca-app-pub-3940256099942544/3986624511"
        ]),
        .release(name: "Release", settings: [
            "CLOUDKIT_CONTAINER_ID": "iCloud.Carve.SwiftData.iCloud",
            "ADMOB_NATIVE_CHART_AD_UNIT_ID": "ca-app-pub-7073697298801242/6417626074"
        ])
    ]
)

let targets: [Target] = [
    // 실기기 터치 자동화 (D9-5 · D9-7). Pencil 입력은 범위 밖이다 — .pencilOnly 라 합성 터치가 무시된다.
    .target(
        name: "\(projectName)UITests",
        destinations: [.iPad],
        product: .uiTests,
        bundleId: .defaultBundleID + ".UITests",
        deploymentTargets: .iOS("17.0"),
        infoPlist: .default,
        sources: ["UITests/**"],
        dependencies: [.target(name: projectName)]
    ),
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
