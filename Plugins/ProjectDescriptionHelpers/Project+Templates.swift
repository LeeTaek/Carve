import ProjectDescription

public extension SettingsDictionary {
    /// Xcode 의 "Update to recommended settings" 가 요구하는 설정 묶음.
    /// 새 항목이 뜨면 아래에 그룹을 추가하고 여기에 머지한다.
    static var xcodeRecommended: Self {
        localization
            .merging(moduleVerifier)
            .merging(userScriptSandboxing)
            .merging(assetSymbols)
    }

    /// Asset Catalog 에서 타입 세이프한 심볼과 `Color`/`Image` 확장을 생성한다.
    /// Tuist 의 resourceSynthesizer 가 만드는 접근자와 타입 이름이 달라 충돌하지 않는다.
    static let assetSymbols: Self = [
        "ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS": "YES",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES"
    ]

    /// 빌드 스크립트를 샌드박스에서 실행한다. 우리 스크립트 페이즈는 SwiftLint 뿐이고
    /// CarveApp·Domain 은 이미 켠 채로 잘 돌고 있어서 나머지 모듈에도 같은 값을 준다.
    static let userScriptSandboxing: Self = [
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES"
    ]

    /// 모듈 헤더가 C/ObjC/C++ 에서 깨끗하게 임포트되는지 빌드 시 검증한다.
    /// 지금 모듈은 전부 순수 Swift 라 검증할 공개 헤더가 없어 사실상 no-op 이고,
    /// 나중에 ObjC 헤더가 생기면 그때부터 자동으로 검사된다.
    static let moduleVerifier: Self = [
        "ENABLE_MODULE_VERIFIER": "YES",
        "MODULE_VERIFIER_SUPPORTED_LANGUAGES": "objective-c objective-c++",
        "MODULE_VERIFIER_SUPPORTED_LANGUAGE_STANDARDS": "gnu17 gnu++20"
    ]

    /// 다국어 대응 준비용 설정. Xcode 의 "Update to recommended settings" 가 요구하는 Localization 항목이다.
    /// - `LOCALIZATION_PREFERS_STRING_CATALOGS`: 로컬라이제이션 추가 시 .strings 대신 String Catalog(.xcstrings) 를 만든다.
    /// - `SWIFT_EMIT_LOC_STRINGS`: 컴파일러가 `Text("...")`, `String(localized:)` 같은 문자열을 카탈로그로 추출한다.
    /// - `STRING_CATALOG_GENERATE_SYMBOLS`: .xcstrings 에서 타입 세이프한 심볼을 생성한다.
    ///
    /// .xcstrings 가 아직 없어서 지금은 동작상 no-op 이고, 카탈로그를 추가하는 순간부터 효과가 있다.
    static let localization: Self = [
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "STRING_CATALOG_GENERATE_SYMBOLS": "YES"
    ]
}

public extension Project {
    static func makeModule(
      name: String,
      organizationName: String = "leetaek",
      packages: [Package] = [],
      targets: [Target],
      schemes: [Scheme] = [],
      settings: Settings? = .settings(
        base: SettingsDictionary()
            .automaticCodeSigning(devTeam: "H4MSW7FUBB")
            .otherLinkerFlags(["-all_load -Objc"])
    ),
      additionalFiles: [FileElement] = [],
      resourceSynthesizers: [ResourceSynthesizer] = []
    ) -> Project {
      // 모듈마다 settings 를 따로 넘기든 기본값을 쓰든 Xcode 권장 설정은 항상 붙는다.
      let mergedSettings: Settings = {
          guard var settings else { return .settings(base: .xcodeRecommended) }
          settings.base = settings.base.merging(.xcodeRecommended)
          return settings
      }()

      return Project(
        name: name,
        organizationName: organizationName,
        options: .options(
            defaultKnownRegions: ["en", "ko"],
            developmentRegion: "ko"
        ),
        packages: packages,
        settings: mergedSettings,
        targets: targets,
        schemes: schemes,
        additionalFiles: additionalFiles,
        resourceSynthesizers: resourceSynthesizers
      )
    }
    
}
