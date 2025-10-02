// swift-tools-version: 6.0
//
//  Library.swift
//  MyPlugin
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription

public extension TargetDependency {
    /// 내부 모듈
    static let CarveApp: Self = .project(target: "App", path: .relativeToRoot("App/CarveApp"))
    static let CarveFeature: Self = .project(target: "CarveFeature", path: .relativeToRoot("Feature/CarveFeature"))
    static let SettingsFeature: Self = .project(target: "SettingsFeature", path: .relativeToRoot("Feature/SettingsFeature"))
    static let Data: Self = .project(target: "Data", path: .relativeToRoot("Data/Data"))
    static let Domain: Self = .project(target: "Domain", path: .relativeToRoot("Domain/Domain"))
    static let CarveToolkit: Self = .project(target: "CarveToolkit", path: .relativeToRoot("Supports/CarveToolkit"))
    static let Resources: Self = .project(target: "Resources", path: .relativeToRoot("Shared/Resources"))
    
    /// 외부 라이브러리: Tuist + SPM
    static let TCAArchitecture: Self = .external(name: "ComposableArchitecture")
    static let Dependencies: Self = .external(name: "Dependencies")
    static let FirebaseAnalytics: Self = .external(name:  "FirebaseAnalytics")
    static let FirebaseMessaging: Self = .external(name:  "FirebaseMessaging")
    static let FirebaseCrashlytics: Self = .external(name: "FirebaseCrashlytics")
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
