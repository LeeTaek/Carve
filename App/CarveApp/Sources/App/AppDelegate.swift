//
//  AppDelegate.swift
//  Carve
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import UIKit

import FirebaseCore
import GoogleMobileAds

class AppDelegate: NSObject, UIApplicationDelegate {
    /// MetricKit 구독은 앱이 살아 있는 동안 유지돼야 한다 (R20 — 저메모리 기기 실태 수집).
    private let metrics = MetricKitReporter(analytics: FirebaseAnalyticsClient())

    /// Firebase 설정
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
#if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.min)
#endif
        MobileAds.shared.start()
        // payload 는 실행 시점에 하루치가 한 번에 오므로 가장 이르게 등록한다.
        metrics.start()

        return true
    }
}
