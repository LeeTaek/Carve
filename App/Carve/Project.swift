import ProjectDescription
import ProjectDescriptionHelpers

let projectName = "Carve"

let dependencies: [TargetDependency] = [
    .FeatureCarve,
    .FeatureLogin,
    .FeatureSettings,
    .FirebaseAnalytics,
    .FirebaseMessaging
]

let script: [TargetScript] = [.swiftLint, .firebaseCrashlytics]

let targets: [Target] = [
    .makeAppTarget(
        name: .configuration(projectName),
        scripts: script,
        dependencies: dependencies
    )
]


let project = Project.makeModule(
    name: projectName,
    targets: targets
) 
