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

