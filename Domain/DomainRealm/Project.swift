//
//  Project.swift
//  ProjectDescriptionHelpers
//
//  Created by 이택성 on 1/29/24.
//

import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "DomainRealm"

let dependencies: [TargetDependency] = [
    .Common
]

let script: [TargetScript] = [.swiftLint]

let target: [Target] = [
    .makeFrameworkTarget(projName: projectName, target: .debug, script: script, dependencies: dependencies),
    .makeTestTarget(projName: projectName, target: .debug, script: script)
]

let project = Project.makeModule(
    name: projectName,
    targets: target
)
