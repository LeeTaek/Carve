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
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleDisplayName": "새기다",
                "UILaunchStoryboardName": "LaunchScreen",
                "UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
                "FeedbackAddress": "$(FEEDBACK_ADDRESS)",
                "UIBackgroundModes": ["remote-notification"],
                "CLOUDKIT_CONTAINER_ID": "$(CLOUDKIT_CONTAINER_ID)",
                "GADApplicationIdentifier": "ca-app-pub-7073697298801242~1655419837",
                "SKAdNetworkItems": .array(
                    skAdNetworkIdentifiers.map { Plist.Value.dictionary(["SKAdNetworkIdentifier": .string($0)]) }
                ),
                "ADMOB_NATIVE_CHART_AD_UNIT_ID": "$(ADMOB_NATIVE_CHART_AD_UNIT_ID)",
                "ADMOB_NATIVE_SIDEBAR_AD_UNIT_ID": "$(ADMOB_NATIVE_SIDEBAR_AD_UNIT_ID)",
                "ADMOB_NATIVE_HEADER_AD_UNIT_ID": "$(ADMOB_NATIVE_HEADER_AD_UNIT_ID)"
            ]
        )
    }

    /// AdMob 광고 구매자의 SKAdNetwork 식별자. 광고로 일어난 설치를 Apple 이 이 네트워크들에 알려 줄 수 있어야 해당 구매자가 입찰한다.
    /// 출처: https://developers.google.com/admob/ios/3p-skadnetworks (2026-09-14 확인, 50개). 목록이 바뀌면 이 페이지를 기준으로 갱신한다.
    private static let skAdNetworkIdentifiers: [String] = [
        "cstr6suwn9.skadnetwork",
        "4fzdc2evr5.skadnetwork",
        "2fnua5tdw4.skadnetwork",
        "ydx93a7ass.skadnetwork",
        "p78axxw29g.skadnetwork",
        "v72qych5uu.skadnetwork",
        "ludvb6z3bs.skadnetwork",
        "cp8zw746q7.skadnetwork",
        "3sh42y64q3.skadnetwork",
        "c6k4g5qg8m.skadnetwork",
        "s39g8k73mm.skadnetwork",
        "wg4vff78zm.skadnetwork",
        "3qy4746246.skadnetwork",
        "f38h382jlk.skadnetwork",
        "hs6bdukanm.skadnetwork",
        "mlmmfzh3r3.skadnetwork",
        "v4nxqhlyqp.skadnetwork",
        "wzmmz9fp6w.skadnetwork",
        "su67r6k2v3.skadnetwork",
        "yclnxrl5pm.skadnetwork",
        "t38b2kh725.skadnetwork",
        "7ug5zh24hu.skadnetwork",
        "gta9lk7p23.skadnetwork",
        "vutu7akeur.skadnetwork",
        "y5ghdn5j9k.skadnetwork",
        "v9wttpbfk9.skadnetwork",
        "n38lu8286q.skadnetwork",
        "47vhws6wlr.skadnetwork",
        "kbd757ywx3.skadnetwork",
        "9t245vhmpl.skadnetwork",
        "a2p9lx4jpn.skadnetwork",
        "22mmun2rn5.skadnetwork",
        "44jx6755aq.skadnetwork",
        "k674qkevps.skadnetwork",
        "4468km3ulz.skadnetwork",
        "2u9pt9hc89.skadnetwork",
        "8s468mfl3y.skadnetwork",
        "klf5c3l5u5.skadnetwork",
        "ppxm28t8ap.skadnetwork",
        "kbmxgpxpgc.skadnetwork",
        "uw77j35x4d.skadnetwork",
        "578prtvx9j.skadnetwork",
        "4dzt52r2t5.skadnetwork",
        "tl55sbb4fm.skadnetwork",
        "c3frkrj4fj.skadnetwork",
        "e5fvkxwrpn.skadnetwork",
        "8c4e2ghe7u.skadnetwork",
        "3rd42ekr43.skadnetwork",
        "97r2b46745.skadnetwork",
        "3qcr597p9d.skadnetwork"
    ]
}
