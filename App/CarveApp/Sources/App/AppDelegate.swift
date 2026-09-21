//
//  AppDelegate.swift
//  Carve
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import UIKit

import FirebaseCore

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
        // 광고 SDK 는 광고 동의(UMP)를 확인한 뒤 AdConsentCoordinator 가 시작한다(ADS-1).
        // payload 는 실행 시점에 하루치가 한 번에 오므로 가장 이르게 등록한다.
        metrics.start()

        return true
    }
}
