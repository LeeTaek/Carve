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
        "CLANG_ENABLE_MODULE_VERIFIER": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES"
    ]
)


let target: [Target] = [
    .makeFrameworkTarget(projName: projectName, target: .debug, script: script, dependencies: dependencies, settings: settings),
    .makeTestTarget(projName: projectName, target: .debug, script: script)
]

let project = Project.makeModule(
    name: projectName,
    targets: target,
    settings: settings
)
