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
            "CFBundleInfoDictionaryVersion": "0.1.0",
            "CFBundlePackageType": "APPL",
            "CFBundleName": "$(PRODUCT_NAME)",
            "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "0.1.0",
            "UILaunchStoryboardName": "LaunchScreen",
            "UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
            "FeedbackAddress": "$(FEEDBACK_ADDRESS)"
          ]
        )
    }
}
