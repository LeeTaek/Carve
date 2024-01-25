import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "Carve"

let dependencies: [TargetDependency] = [
    .Feature,
    .Core,
    .Shared,
    
    .FirebaseAnalytics,
    .FirebaseMessaging
]

let script: [TargetScript] = [.swiftLint]

let targets: [Target] = [
    .makeAppTarget(name: .configuration(projectName), scripts: script, dependencies: dependencies)
]

let project = Project.makeModule(
    name: projectName,
    targets: targets
)
