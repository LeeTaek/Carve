//
//  MetricKitReporter.swift
//  CarveApp
//
//  R20 — 보유하지 않은 기기의 메모리 실태를 사용자에게서 받는다 (2026-09-09 신설).
//
//  ## 왜 필요한가
//  저메모리 iPad 와 ProMotion 기기가 없어 사전 테스트가 불가능하다. 보유 기기(8 GB)의 jetsam 한도는
//  실측 3376 MB 였고 긴 장에서 peak 이 1839 MB 였으나, **한도가 RAM 에 비례한다는 가정은 한 점에서 뽑은 외삽**이라
//  어느 기기가 실제로 죽는지는 알 수 없다. MetricKit 은 그 답을 **실제 사용자 기기에서** 가져온다.
//
//  보는 값은 `cumulativeMemoryResourceLimitExitCount` — 메모리 한도로 종료된 횟수다.
//  기기 모델은 Firebase Analytics 가 자동으로 붙이므로 따로 보내지 않는다.
//
//  payload 는 하루 한 번, 앱 실행 시점에 도착한다. 그래서 등록은 `AppDelegate` 에서 가장 이르게 한다.
//

import ClientInterfaces
import Foundation
import MetricKit

/// MetricKit 일일 payload 를 Analytics 로 옮긴다.
final class MetricKitReporter: NSObject, MXMetricManagerSubscriber {
    private let analytics: any AnalyticsClient

    init(analytics: any AnalyticsClient) {
        self.analytics = analytics
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
        #if DEBUG
        // 기기에 이미 쌓인 과거 payload 로 **매핑만** 확인한다. payload 는 하루 한 번만 도착하므로
        // 이것이 아니면 배포 전에 이 경로를 태울 방법이 없다. 분석 이벤트는 보내지 않는다.
        let past = MXMetricManager.shared.pastPayloads
        print("MetricKitProbe pastPayloads=\(past.count)")
        for payload in past { print("MetricKitProbe \(Self.parameters(from: payload))") }
        #endif
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { report(payload) }
    }

    private func report(_ payload: MXMetricPayload) {
        let parameters = Self.parameters(from: payload)
        analytics.track("mk_daily", parameters: parameters)

        // 한도로 죽은 적이 있으면 따로 남긴다 — 이것만 보면 되도록.
        let memoryKills = (parameters["mem_exit_fg"].flatMap(Self.intValue) ?? 0)
            + (parameters["mem_exit_bg"].flatMap(Self.intValue) ?? 0)
        if memoryKills > 0 {
            analytics.track("mk_memory_kill", parameters: [
                "count": .int(memoryKills),
                "peak_mb": parameters["peak_mb"] ?? .int(0)
            ])
        }
    }

    private static func intValue(_ value: AnalyticsValue) -> Int? {
        if case let .int(number) = value { return number }
        return nil
    }

    /// payload → Analytics 파라미터. **순수 변환이라 여기만 보면 어떤 값이 올라가는지 알 수 있다.**
    ///
    /// Firebase 규칙에 맞춰 이름은 40자 이내·영문 시작이고 예약 접두사(`firebase_`·`google_`·`ga_`)를 쓰지 않는다.
    /// 기기 모델은 Firebase 가 자동으로 붙이므로 넣지 않는다.
    static func parameters(from payload: MXMetricPayload) -> [String: AnalyticsValue] {
        let foreground = payload.applicationExitMetrics?.foregroundExitData
        let background = payload.applicationExitMetrics?.backgroundExitData
        var parameters: [String: AnalyticsValue] = [
            "mem_exit_fg": .int(foreground?.cumulativeMemoryResourceLimitExitCount ?? 0),
            "mem_exit_bg": .int(background?.cumulativeMemoryResourceLimitExitCount ?? 0),
            "mem_pressure_bg": .int(background?.cumulativeMemoryPressureExitCount ?? 0),
            // 분모 — 종료 횟수만 보면 사용량이 는 것인지 나빠진 것인지 구분되지 않는다.
            "exit_fg_normal": .int(foreground?.cumulativeNormalAppExitCount ?? 0)
        ]
        if let peak = payload.memoryMetrics?.peakMemoryUsage {
            parameters["peak_mb"] = .int(Int(peak.converted(to: .megabytes).value.rounded()))
        }
        return parameters
    }
}
