//
//  Project.swift
//  ProjectDescriptionHelpers
//
//  Created by 이택성 on 2/20/24.
//

import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "DependencyInjection"

let dependencies: [TargetDependency] = [
    .Common,
    .CoreRealm,
    .DomainRealm,
    .RealmSwift
]

let script: [TargetScript] = [.swiftLint]

let targets: [Target] = [
    .makeFrameworkTarget(projName: projectName, target: .debug, script: script, dependencies: dependencies),
    .makeTestTarget(projName: projectName, target: .debug, script: script)
]

let project = Project.makeModule(
    name: projectName,
    targets: targets
)
