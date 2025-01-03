//
//  Project.swift
//  CarveAppManifests
//
//  Created by 이택성 on 11/22/24.
//

import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "UIComponent"

let dependencies: [TargetDependency] = [
]

let script: [TargetScript] = [.swiftLint]

let settings: Settings = .settings(
    base: [
        "CLANG_ENABLE_MODULE_VERIFIER": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES"
    ]
)

let target: [Target] = [
    .makeFrameworkTarget(projName: projectName, target: .debug, script: script, dependencies: dependencies),
    .makeTestTarget(projName: projectName, target: .debug, script: script)
]

let project = Project.makeModule(
    name: projectName,
    targets: target
)