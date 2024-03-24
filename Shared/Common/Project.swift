//
//  Project.swift
//  ProjectDescriptionHelpers
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "Common"

let target: [Target] = [
    .makeFrameworkTarget(projName: projectName, target: .debug)
]

let project = Project.makeModule(
    name: projectName,
    targets: target
)
