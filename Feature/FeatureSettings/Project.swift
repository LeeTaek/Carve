//
//  Project.swift
//  ProjectDescriptionHelpers
//
//  Created by 이택성 on 1/26/24.
//

import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "FeatureSettings"

let dependencies: [TargetDependency] = [
    .DependencyInjection,
    .DomainRealm,
    .TCAArchitecture,
    .TCACoordinator,
    .Kingfisher
]

let script: [TargetScript] = [.swiftLint]

let settings: Settings = .settings(configurations: [
    .debug(name: .debug),
    .release(name: .release)
])


let target: [Target] = [
    .makeFrameworkTarget(
        projName: projectName,
        target: .debug,
        resources: "Resources/**",
        script: script,
        dependencies: dependencies,
        settings: settings
    ),
    .makeTestTarget(projName: projectName, target: .debug, script: script)
]


let project = Project.makeModule(
    name: projectName,
    targets: target,
    resourceSynthesizers: [.assets()]
)
