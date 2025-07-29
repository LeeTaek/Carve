//
//  Project.swift
//  CarveEnvironment
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription
import CarveEnvironment

let projectName = "CarveToolkit"

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
