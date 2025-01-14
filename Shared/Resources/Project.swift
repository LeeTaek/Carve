//
//  Project.swift
//  CarveEnvironment
//
//  Created by openobject on 2023/08/28.
//

import ProjectDescription
import CarveEnvironment

let projectName = "Resources"

let targets: [Target] = [
  .makeFrameworkTarget(
    projName: projectName,
    target: .debug,
    product: .framework,
    resources: "Resources/**"
  )
]

let project = Project.makeModule(
  name: projectName,
  targets: targets,
  resourceSynthesizers: [
    .assets(),
    .fonts()
  ]
)

