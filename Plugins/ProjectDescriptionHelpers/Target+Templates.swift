//
//  Target+Templates.swift
//  CarveEnvironment
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription
import CarveEnvironment

public extension Target {
    static func makeAppTarget(
        name: String,
        destination: Destinations = [.iPad],
        product: Product = .app,
        bundleID: String = .defaultBundleID,
        deploymentTarget: DeploymentTargets = .iOS("17.0"),
        infoPlist: InfoPlist = .infoPlist,
        sources: SourceFilesList = "Sources/**",
        resources: ResourceFileElements? = [
            "Resources/**",
            "./Support/GoogleService-Info.plist",
            "./Support/PrivacyInfo.xcprivacy"
        ],
        entitlements: Entitlements? = nil,
        scripts: [ProjectDescription.TargetScript] = [],
        dependencies: [TargetDependency] = [],
        settings: Settings? = nil,
        launchArguments: [ProjectDescription.LaunchArgument] = []
    )
    -> Target {
        return Target.target(
            name: name,
            destinations: destination,
            product: product,
            bundleId: bundleID,
            deploymentTargets: deploymentTarget,
            infoPlist: infoPlist,
            sources: sources,
            resources: resources,
            entitlements: entitlements,
            scripts: scripts,
            dependencies: dependencies,
            settings: settings,
            launchArguments: launchArguments
        )
    }
    
    
    
    /// WIDGET-0 스파이크 — 위젯(app extension) 타깃. 기존 makeAppTarget 관용구를 그대로 따른다.
    /// 서명은 프로젝트 레벨 automaticCodeSigning 을 상속하므로 여기서 다시 지정하지 않는다.
    static func makeWidgetExtensionTarget(
        name: String,
        destination: Destinations = [.iPad],
        bundleID: String = .defaultBundleID + ".Widget",
        deploymentTarget: DeploymentTargets = .iOS("17.0"),
        displayName: String,
        sources: SourceFilesList,
        resources: ResourceFileElements? = nil,
        entitlements: Entitlements? = nil,
        dependencies: [TargetDependency] = []
    ) -> Target {
        return Target.target(
            name: name,
            destinations: destination,
            product: .appExtension,
            bundleId: bundleID,
            deploymentTargets: deploymentTarget,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": .string(displayName),
                // ⚠️ 앱 Info.plist 는 이 값을 리터럴 "1.3.1" 로 박아 두었다. 위젯은 빌드 설정을 참조한다.
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "NSExtension": .dictionary([
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
                ])
            ]),
            sources: sources,
            resources: resources,
            entitlements: entitlements,
            dependencies: dependencies
        )
    }

    static func makeTestTarget(
        projName: String,
        destination: Destinations = [.iPad],
        target: ConfigurationName,
        product: Product = .unitTests,
        bundleID: String = .defaultBundleID,
        deploymentTarget: DeploymentTargets = .iOS("17.0"),
        infoPlist: InfoPlist = .default,
        testSources: SourceFilesList? = nil,
        script: [TargetScript] = [],
        dependencies: [TargetDependency] = []
    ) -> Target {
        return Target.target(
            name: "\(projName)Test",
            destinations: destination,
            product: product,
            bundleId: bundleID + ".\(projName).Test",
            deploymentTargets: deploymentTarget,
            infoPlist: infoPlist,
            sources: ["Tests/**"],
            scripts: script,
            dependencies: dependencies
        )
    }
    
    static func makeFrameworkTarget(
        projName: String,
        destination: Destinations = [.iPad],
        target: ConfigurationName,
        product: Product = Environment.forPreview.getBoolean(default: false) ? .framework : .staticFramework,
        bundleID: String = .defaultBundleID,
        deploymentTarget: DeploymentTargets = .iOS("17.0"),
        infoPlist: InfoPlist? = .default,
        sources: SourceFilesList? = "Sources/**",
        resources: ResourceFileElements? = nil,
        entitlements: Entitlements? = nil,
        script: [TargetScript] = [],
        dependencies: [TargetDependency] = [],
        settings: Settings? = nil
    )
    -> Target {
        return Target.target(
            name: projName,
            destinations: destination,
            product: product,
            bundleId: bundleID + target.rawValue + ".\(projName)",
            deploymentTargets: deploymentTarget,
            infoPlist: infoPlist,
            sources: sources,
            resources: resources,
            entitlements: entitlements,
            scripts: script,
            dependencies: dependencies,
            settings: settings
        )
    }
}


public extension String {
    static let defaultBundleID = "kr.co.carve.leetaek"
}

