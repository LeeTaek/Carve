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
    .GoogleUMP,

    .TCAArchitecture
]

let script: [TargetScript] = [.swiftLint, .firebaseCrashlytics]

let settings: Settings = .settings(
    base: SettingsDictionary()
        .automaticCodeSigning(devTeam: "H4MSW7FUBB")
        .otherLinkerFlags(["-all_load -Objc"])
        .debugInformationFormat(.dwarfWithDsym)
        .marketingVersion("2.0.0")
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
            // Debug 는 모든 위치에 Google 공개 테스트 네이티브 단위를 쓴다.
            "ADMOB_NATIVE_CHART_AD_UNIT_ID": "ca-app-pub-3940256099942544/3986624511",
            "ADMOB_NATIVE_SIDEBAR_AD_UNIT_ID": "ca-app-pub-3940256099942544/3986624511",
            "ADMOB_NATIVE_HEADER_AD_UNIT_ID": "ca-app-pub-3940256099942544/3986624511"
        ]),
        .release(name: "Release", settings: [
            "CLOUDKIT_CONTAINER_ID": "iCloud.Carve.SwiftData.iCloud",
            "ADMOB_NATIVE_CHART_AD_UNIT_ID": "ca-app-pub-7073697298801242/6417626074",
            "ADMOB_NATIVE_SIDEBAR_AD_UNIT_ID": "ca-app-pub-7073697298801242/8915591660",
            "ADMOB_NATIVE_HEADER_AD_UNIT_ID": "ca-app-pub-7073697298801242/1591248377"
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
        // Asset.xcassets 에 AccentColor 색상 세트가 없어서 actool 경고가 난다. 기본 틴트를 쓴다.
        // tuist 가 타깃 레벨에 기본값을 넣으므로 프로젝트 base 가 아니라 여기서 비워야 먹는다.
        settings: .settings(base: ["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": ""]),
        launchArguments: [
            .launchArgument(name: "-FIRDebugEnabled", isEnabled: true)
        ]
    )
]


/// 시뮬레이터에서 광고 제거 구매를 시험하는 스킴. 실행(Run)만 로컬 StoreKit 설정(`Support/Carve.storekit`)을 쓴다.
/// Xcode Cloud · 아카이브는 자동 생성되는 `CarveApp` 스킴을 그대로 쓰므로 StoreKit 설정이 섞이지 않는다.
let storeKitScheme: Scheme = .scheme(
    name: "\(projectName)-StoreKit",
    buildAction: .buildAction(targets: [.target(projectName)]),
    runAction: .runAction(
        configuration: .debug,
        executable: .target(projectName),
        arguments: .arguments(launchArguments: [
            .launchArgument(name: "-FIRDebugEnabled", isEnabled: true)
        ]),
        options: .options(storeKitConfigurationPath: .relativeToManifest("Support/Carve.storekit"))
    )
)

let project = Project.makeModule(
    name: projectName,
    targets: targets,
    schemes: [storeKitScheme],
    settings: settings,
    // 앱 번들에 넣지 않고 Xcode 에서 편집(가격 · 거래 관리)만 할 수 있게 네비게이터에 둔다.
    additionalFiles: ["Support/Carve.storekit"]
)
