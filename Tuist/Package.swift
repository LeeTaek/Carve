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
        "CasePathsCore": .framework
    ] : [:] ,
    // Firebase·Google SDK 들이 빈 .o(dummy.o, placeholder.o, NSError+FIRMessaging.o ...)를 넣어두는 탓에
    // libtool 이 "has no symbols" 경고를 낸다. 3자 코드라 손댈 수 없으니 의존성 프로젝트에서만 끈다.
    baseSettings: .settings(base: ["OTHER_LIBTOOLFLAGS": "-no_warning_for_no_symbols"]),
    targetSettings: [
        // Xcode 권장 설정. 이 타깃은 헤더가 있어서 모듈 검증 대상이 된다.
        // 배포 타깃은 앱 최소치(iOS 17)에 맞춘다. 앱보다 높이면 그 아래 OS 에서 링크가 깨지므로 17 을 넘기지 않는다.
        "GoogleMobileAdsTarget": .moduleVerifier.merging(["IPHONEOS_DEPLOYMENT_TARGET": "17.0"]),
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
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.2"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", .upToNextMajor(from: "12.14.0"))
    ]
)
