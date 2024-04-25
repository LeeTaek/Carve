//
//  Project.swift
//  ProjectDescriptionHelpers
//
//  Created by 이택성 on 1/29/24.
//

import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "Domain"

let dependencies: [TargetDependency] = [
    .Core
]

let script: [TargetScript] = [.swiftLint]

let settings: Settings = .settings(
    base: [
        "SWIFT_STRICT_CONCURRENCY": "complete"
    ],
    configurations: [
        .debug(name: .debug),
        .release(name: .release)
    ]
)


let target: [Target] = [
    .makeFrameworkTarget(projName: projectName, target: .debug, script: script, dependencies: dependencies/*, settings: settings*/),
    .makeTestTarget(projName: projectName, target: .debug, script: script)
]

let project = Project.makeModule(
    name: projectName,
    targets: target,
    settings: settings
)
