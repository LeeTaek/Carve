//
//  FirebaseAnalyticsClient.swift
//  CarveApp
//
//  Created by 이택성 on 2/24/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import FirebaseAnalytics
import ClientInterfaces

struct FirebaseAnalyticsClient: AnalyticsClient {
    func track(_ name: String, parameters: [String: AnalyticsValue]) {
        Analytics.logEvent(name, parameters: parameters.mapValues { $0.rawAny })
    }
    
    func screen(_ name: String, parameters: [String : AnalyticsValue]) {
        Analytics.logEvent("screen_view", parameters: [
            "screen_name": name,
            "screen_class": name
        ].merging(parameters.mapValues { $0.rawAny }) { left, _ in left })
    }
}
