//
//  InfoPlist.swift
//  MyPlugin
//
//  Created by 이택성 on 1/25/24.
//

import ProjectDescription

public extension InfoPlist {
    static var infoPlist: Self {
        .extendingDefault(
          with: [
            "CFBundleExecutable": "$(EXECUTABLE_NAME)",
            "CFBundleInfoDictionaryVersion": "1.0.0",
            "CFBundlePackageType": "APPL",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleDisplayName": "새기다",
            "UILaunchStoryboardName": "LaunchScreen",
            "UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
            "FeedbackAddress": "$(FEEDBACK_ADDRESS)",
            "UIBackgroundModes": ["remote-notification"],
            "UIUserInterfaceStyle": "Light"
          ]
        )
    }
}
