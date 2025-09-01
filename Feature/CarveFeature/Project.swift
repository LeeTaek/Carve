// swift-tools-version: 6.0
//
//  Project.swift
//  CarveEnvironment
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription
import CarveEnvironment

let projectName = "CarveFeature"

let dependencies: [TargetDependency] = [
    .Domain,
    .UIComponents,
    .TCAArchitecture,
    .Resources
    
]

let script: [TargetScript] = [.swiftLint]

let settings: Settings = .settings(
    base: [
        "CLANG_ENABLE_MODULE_VERIFIER": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES"
    ],
    configurations: [
        .debug(name: .debug),
        .release(name: .release)
    ]
)


let target: [Target] = [
    .makeFrameworkTarget(
        projName: projectName,
        target: .debug,
        resources: .resources([
            "Resources/**"
        ]),
        script: script,
        dependencies: dependencies,
        settings: settings
    ),
    .makeTestTarget(projName: projectName, target: .debug, script: script, dependencies: [.target(name: projectName)])
]


let project = Project.makeModule(
    name: projectName,
    targets: target,
    resourceSynthesizers: [
        .assets()
    ]
)
