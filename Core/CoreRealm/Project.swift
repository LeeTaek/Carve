//
//  Project.swift
//  ProjectDescriptionHelpers
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "CoreRealm"

let dependencies: [TargetDependency] = [
    .Common,
    .DomainRealm,
    .Alamofire,
    .RealmSwift
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
