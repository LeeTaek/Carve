// swift-tools-version: 5.9
//
//  Package.swift
//  Config
//
//  Created by 이택성 on 3/13/24.
//

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

//let packageSettings = PackageSettings.packages
#endif

let packages = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from:  "5.8.1"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from:  "7.9.1"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.15.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.10.4"),
        .package(url: "https://github.com/johnpatrickmorgan/TCACoordinators", from: "0.10.0")
    ]
)
