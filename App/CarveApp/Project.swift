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
        .marketingVersion("2.0.1")
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
    // 광고 제거 StoreKit 시험(시뮬레이터)은 로컬 StoreKit 설정을 이 번들에서 읽는다 — 앱 번들에는 넣지 않는다.
    .target(
        name: "\(projectName)UITests",
        destinations: [.iPad],
        product: .uiTests,
        bundleId: .defaultBundleID + ".UITests",
        deploymentTargets: .iOS("17.0"),
        infoPlist: .default,
        sources: [
            "UITests/**",
            // 실행 인자 이름은 CarveToolkit 이 갖는다. UI 테스트는 모듈을 링크하지 않고 소스로 함께 컴파일한다.
            "../../Supports/CarveToolkit/Sources/LaunchArgument/LaunchArgument.swift"
        ],
        resources: ["Support/Carve.storekit"],
        dependencies: [.target(name: projectName)]
    ),
    // 앱 단위 테스트. 호스트 앱 없이 돈다 — 앱 타깃에 의존하지 않고, 시험할 앱 소스만 함께 컴파일한다.
    // 앱 타깃(Sources)에 새로 만든 파일은 여기서 컴파일되지 않는다. 코디네이터가 쓰는 타입은 아래 파일 안이나 Feature · Supports 모듈에 둔다.
    .makeTestTarget(
        projName: projectName,
        target: .debug,
        testSources: [
            "Tests/**",
            "Sources/Coordinator/AppCoordinatorFeature.swift",
            "Sources/App/LaunchProgressFeature.swift",
            "Widget/Shared/VerseWidgetPayload.swift"
        ],
        script: [.swiftLint],
        dependencies: [
            .CarveFeature,
            .ChartFeature,
            .SettingsFeature,
            .ClientInterfaces,
            .TCAArchitecture
        ]
    ),
    // 위젯(시안 N6~N9). 앱이 이 타깃에 의존해야 Tuist 가 PlugIns 에 임베드한다 (WIDGET-0 §1).
    .makeWidgetExtensionTarget(
        name: "CarveWidget",
        displayName: "새기다",
        sources: [
            "Widget/Sources/**",
            "Widget/Shared/**",
            // 도는 순서 규칙은 Domain 이 갖고 Domain 테스트가 지킨다. 위젯은 링크하지 않고 소스로 함께 컴파일한다.
            "../../Domain/Domain/Sources/Widget/WidgetVerseRotation.swift"
        ],
        entitlements: .file(path: .relativeToCurrentFile("Support/CarveWidget.entitlements"))
    ),
    .makeAppTarget(
        name: projectName,
        // 위젯과 함께 컴파일하는 공유 페이로드. 위젯은 Domain · SwiftData 를 링크하지 않는다.
        sources: ["Sources/**", "Widget/Shared/**"],
        entitlements: .file(path: .relativeToCurrentFile("Support/Carve.entitlements")),
        scripts: script,
        dependencies: dependencies + [.target(name: "CarveWidget")],
        // Asset.xcassets 에 AccentColor 색상 세트가 없어서 actool 경고가 난다. 기본 틴트를 쓴다.
        // tuist 가 타깃 레벨에 기본값을 넣으므로 프로젝트 base 가 아니라 여기서 비워야 먹는다.
        settings: .settings(base: ["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": ""]),
        launchArguments: [
            .launchArgument(name: "-FIRDebugEnabled", isEnabled: true)
        ]
    )
]


/// 시뮬레이터에서 광고 제거 구매를 시험하는 스킴. 실행(Run)은 로컬 StoreKit 설정(`Support/Carve.storekit`)을 쓴다.
/// 테스트는 `RemoveAdsStoreKitUITests` 를 켠다(`CARVE_STOREKIT_UITEST=1`) — 표준 `Carve-Workspace` 실행에서는 건너뛴다.
/// Xcode Cloud · 아카이브는 자동 생성되는 `CarveApp` 스킴을 그대로 쓰므로 StoreKit 설정이 섞이지 않는다.
let storeKitScheme: Scheme = .scheme(
    name: "\(projectName)-StoreKit",
    buildAction: .buildAction(targets: [.target(projectName)]),
    testAction: .targets(
        [.testableTarget(target: .target("\(projectName)UITests"))],
        arguments: .arguments(environmentVariables: ["CARVE_STOREKIT_UITEST": "1"])
    ),
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
