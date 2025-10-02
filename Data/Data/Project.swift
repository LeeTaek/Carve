//
//  Project.swift
//  CarveAppManifests
//
//  Created by 이택성 on 10/2/25.
//

import ProjectDescription
import CarveEnvironment

let projectName = "Data"

let dependencies: [TargetDependency] = [
    .Domain,
    .CarveToolkit,
    
    .Dependencies
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
    .makeTestTarget(projName: projectName, target: .debug, script: script, dependencies: [.target(name: projectName)])
]

let project = Project.makeModule(
    name: projectName,
    targets: target,
    settings: settings
)
