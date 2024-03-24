//
//  Project.swift
//  ProjectDescriptionHelpers
//
//  Created by 이택성 on 1/30/24.
//

import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "CommonUI"

let dependencies: [TargetDependency] =  [
    .TCAArchitecture
]

let target: [Target] = [
    .makeFrameworkTarget(projName: projectName, target: .debug, dependencies: dependencies)
]

let project = Project.makeModule(
    name: projectName,
    targets: target
)
