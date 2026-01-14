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
                "CFBundleShortVersionString": "1.2.2",
                "CFBundleDisplayName": "새기다",
                "UILaunchStoryboardName": "LaunchScreen",
                "UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
                "FeedbackAddress": "$(FEEDBACK_ADDRESS)",
                "UIBackgroundModes": ["remote-notification"],
                "UIUserInterfaceStyle": "Light",
                "CLOUDKIT_CONTAINER_ID": "$(CLOUDKIT_CONTAINER_ID)",
                "GADApplicationIdentifier": "ca-app-pub-7073697298801242~1655419837",
                "SKAdNetworkItems": [
                    ["SKAdNetworkIdentifier": "cstr6suwn9.skadnetwork"]
                ],
                "ADMOB_NATIVE_CHART_AD_UNIT_ID": "$(ADMOB_NATIVE_CHART_AD_UNIT_ID)"
            ]
        )
    }
}
