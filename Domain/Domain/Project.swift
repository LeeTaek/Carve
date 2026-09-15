//
//  Project.swift
//  CarveEnvironment
//
//  Created by 이택성 on 1/29/24.
//

import ProjectDescription
import CarveEnvironment

let projectName = "Domain"

let dependencies: [TargetDependency] = [
    .CarveToolkit,
    .ClientInterfaces,
    .Resources,
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

// 모듈 설정은 타깃에만 넘긴다. `makeModule` 에 settings 를 넘기면 프로젝트 기본값(자동 서명 · 개발 팀)이 빠져
// Domain · DomainTest 의 서명이 지정되지 않는다 — 다른 모듈과 같은 구조를 따른다.
let project = Project.makeModule(
    name: projectName,
    targets: target
)
