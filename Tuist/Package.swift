// swift-tools-version: 6.0
//
//  Package.swift
//  Config
//
//  Created by 이택성 on 3/13/24.
//

import PackageDescription


#if TUIST
import ProjectDescription
import CarveEnvironment

let packageSettings = PackageSettings(
    productTypes: Environment.forPreview.getBoolean(default: false) ? [
        "ComposableArchitecture": .framework,
        "Dependencies": .framework,
        "CombineSchedulers": .framework,
        "Sharing": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "UIKitNavigationShim": .framework,
        "ConcurrencyExtras": .framework,
        "Clocks": .framework,
        "CustomDump": .framework,
        "IdentifiedCollections": .framework,
        "XCTestDynamicOverlay": .framework,
        "IssueReporting": .framework,
        "_CollectionsUtilities": .framework,
        "PerceptionCore": .framework,
        "Perception": .framework,
        "OrderedCollections": .framework,
        "CasePaths": .framework,
        "DependenciesMacros": .framework,
    ] : [:] ,
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

#endif

let package = Package(
    name: "Carve",
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", .upToNextMajor(from: "10.29.0")),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", .upToNextMajor(from: "1.17.1"))
    ]
)
