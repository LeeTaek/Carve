// swift-tools-version: 5.9
//
//  Library.swift
//  MyPlugin
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription

extension PackageSettings {
    public static let packages: Self = .init(
        productTypes: [
            "Alamofire": .framework,
            "Kingfisher": .framework,
        ],
        targetSettings: [
            "FBLPromises": .objc,
            "nanopb": .objc,
            "Firebase": .objc,
            "FirebaseAnalyticsWrapper": .objc,
            "FirebaseAnalyticsSwiftTarget": .objc,
            "GoogleAppMeasurementTarget": .objc,
            "GoogleUtilities-AppDelegateSwizzler": .objc,
            "GoogleUtilities-MethodSwizzler": .objc,
            "third-party-IsAppEncrypted": .objc,
            "GoogleUtilities-objc": .objc,
            "GoogleUtilities-Environment": .objc,
            "GoogleUtilities-Logger": .objc,
            "GoogleUtilities-Network": .objc,
            "GoogleUtilities-NSData": .objc,
            "GoogleUtilities-Reachability": .objc,
            "GoogleUtilities-UserDefaults": .objc,
            "gRPC-Core": [
                "GCC_PREPROCESSOR_DEFINITIONS": "$(inherited) GRPC_NO_BINDER=0 GRPC_ARES=0"
            ]
        ]
    )
}


public extension TargetDependency {
    /// 내부 모듈
    static let App: Self = .project(target: "App", path: .relativeToRoot("App/Carve"))
    static let FeatureCarve: Self = .project(target: "FeatureCarve", path: .relativeToRoot("Feature/FeatureCarve"))
    static let FeatureSettings: Self = .project(target: "FeatureSettings", path: .relativeToRoot("Feature/FeatureSettings"))
    static let Domain: Self = .project(target: "Domain", path: .relativeToRoot("Domain/Domain"))
    static let Core: Self = .project(target: "Core", path: .relativeToRoot("Core/Core"))
    static let Resources: Self = .project(target: "Resources", path: .relativeToRoot("Shared/Resources"))

    
    /// 외부 라이브러리: Tuist + SPM
    static let TCAArchitecture: Self = .external(name: "ComposableArchitecture")
    static let FirebaseAnalytics: Self = .external(name:  "FirebaseAnalytics")
    static let FirebaseMessaging: Self = .external(name:  "FirebaseMessaging")
    static let FirebaseCrashlytics: Self = .external(name: "FirebaseCrashlytics")
    static let Kingfisher: Self = .external(name: "Kingfisher")
    static let Alamofire: Self = .external(name: "Alamofire")
}


public extension SettingsDictionary {
    static let objc: Self = [
        "OTHER_LDFLAGS": "-ObjC",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    ]
    
    static let dynamicLibrary: Self = [
        "MACH_O_TYPE": "DYNAMIC_LIBRARY"
    ]
}
