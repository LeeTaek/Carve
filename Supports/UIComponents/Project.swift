//
//  Project.swift
//  CarveAppManifests
//
//  Created by 이택성 on 8/28/25.
//

import ProjectDescription
import CarveEnvironment

let projectName = "UIComponents"

let dependencies: [TargetDependency] = [
    .TCAArchitecture,
    .ClientInterfaces,
    .CarveToolkit
        
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
