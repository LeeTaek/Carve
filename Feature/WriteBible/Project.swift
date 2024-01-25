// swift-tools-version: 5.9
//
//  Project.swift
//  ProjectDescriptionHelpers
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "Feature"

let dependencies: [TargetDependency] = [
    .Core,
    
    .TCAArchitecture,
    .TCACoordinator,
    .Kingfisher
]

let packages: [Package] = [
    .TCA,
    .TCACoordinator,
]

let script: [TargetScript] = [.swiftLint]

let target: [Target] = [
    .makeFrameworkTarget(projName: projectName, target: .debug, resources: "Resources/**", script: script, dependencies: dependencies),
    .makeTestTarget(projName: projectName, target: .debug, script: script)
]

let settings: Settings = .settings(configurations: [
    .debug(name: .debug),
    .release(name: .release)
])

let project = Project.makeModule(
    name: projectName,
    packages: packages,
    targets: target,
    settings: settings,
    resourceSynthesizers: [.assets()]
)
