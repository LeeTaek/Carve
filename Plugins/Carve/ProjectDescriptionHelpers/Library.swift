// swift-tools-version: 5.9
//
//  Library.swift
//  MyPlugin
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription

extension SwiftPackageManagerDependencies {
    public static var packages: Self = .init(
        [
            .Firebase,
            .Kingfisher,
            .Alamofire,
        ],
        productTypes: [
            "Alamofire": .framework,
        ],
        targetSettings: [
            "FBLPromises": .objc,
            "nanopb": .objc,
            "NuguObjcUtils": .objc,
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
            "GoogleUtilities-UserDefaults": .objc
        ]
    )
}



public extension Package {
    static let TCA = Self.remote(url: "https://github.com/pointfreeco/swift-composable-architecture", requirement: .upToNextMajor(from: "1.6.0"))
    static let TCACoordinator = Self.remote(url: "https://github.com/johnpatrickmorgan/TCACoordinators", requirement: .upToNextMajor(from: "0.8.0"))
    static let Firebase = Self.remote(url: "https://github.com/firebase/firebase-ios-sdk.git", requirement: .upToNextMajor(from: "10.15.0"))
    static let Kingfisher = Self.remote(url: "https://github.com/onevcat/Kingfisher.git", requirement: .upToNextMajor(from: "7.9.1"))
    static let Alamofire = Self.remote(url: "https://github.com/Alamofire/Alamofire", requirement: .upToNextMajor(from: "5.8.1"))
    static let Realm = Self.remote(url: "https://github.com/realm/realm-swift", requirement: .upToNextMajor(from: "10.45.3"))
    
    static let SwiftSyntax = Self.package(url: "https://github.com/apple/swift-syntax.git", from: "509.1.1")
}

public extension TargetDependency {
    /// 내부 모듈
    static let App: Self = .project(target: "App", path: .relativeToRoot("App/Carve"))
    static let Feature: Self = .project(target: "Feature", path: .relativeToRoot("Feature/WriteBible"))
    static let Core: Self = .project(target: "Core", path: .relativeToRoot("Core/Core"))
    static let Shared: Self = .project(target: "Shared", path: .relativeToRoot("Shared/Common"))
    
    /// 외부 라이브러리: SPM
    static let TCAArchitecture: Self = .package(product: "ComposableArchitecture")
    static let TCACoordinator: Self = .package(product: "TCACoordinators")
    static let Realm: Self = .package(product: "Realm")

    
    /// 외부 라이브러리: Tuist + SPM
    static let FirebaseAnalytics: Self = .external(name:  "FirebaseAnalyticsSwift")
    static let FirebaseMessaging: Self = .external(name:  "FirebaseMessaging")
    static let Kingfisher: Self = .external(name: "Kingfisher")
    static let Alamofire: Self = .external(name: "Alamofire")
    
}


public extension SettingsDictionary {
    static let objc: Self = [
        "OTHER_LDFLAGS": "-ObjC",
        "DEFINES_MODULE": false
    ]
    
    static let dynamicLibrary: Self = [
        "MACH_O_TYPE": "DYNAMIC_LIBRARY"
    ]
}
