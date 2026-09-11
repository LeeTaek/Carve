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
    .CarveToolkit,
    // 디자인 토큰(색·아이콘)을 직접 읽는다. CarveToolkit 을 거친 전이 의존에 기대지 않는다.
    .Resources
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
    .makeTestTarget(projName: projectName, target: .debug, script: script, dependencies: [.target(name: projectName)])
]

let project = Project.makeModule(
    name: projectName,
    targets: target
)
