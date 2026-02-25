//
//  AnalyticsClient.swift
//  ClientInterfaces
//
//  Created by 이택성 on 2/23/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import Dependencies

/// Analytics 파라미터 값 타입
public enum AnalyticsValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    
    public var rawAny: Any {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return value
        case let .double(value):
            return value
        case let .bool(value):
            return value
        }
    }
}

/// Feature에서 사용될 실제 interface
public protocol AnalyticsClient: Sendable {
    func track(_ name: String, parameters: [String: AnalyticsValue])
    func screen(_ name: String, parameters: [String: AnalyticsValue])
}

public extension AnalyticsClient {
    func track(_ name: String) {
        track(name, parameters: [:])
    }
    
    func screen(_ name: String) {
        screen(name, parameters: [:])
    }
}

private enum AnalyticsClientKey: DependencyKey {
    static let liveValue: any AnalyticsClient = UnimplementedAnalyticsClient()
    static let testValue: any AnalyticsClient = UnimplementedAnalyticsClient()
}

public extension DependencyValues {
    var analyticsClient: any AnalyticsClient {
        get { self[AnalyticsClientKey.self] }
        set { self[AnalyticsClientKey.self] = newValue }
    }
}

private struct UnimplementedAnalyticsClient: AnalyticsClient {
    func track(_ name: String, parameters: [String: AnalyticsValue]) {
        // App/Infra에서 live 구현을 등록하기 전까지는 no-op
    }

    func screen(_ name: String, parameters: [String: AnalyticsValue]) {
        // App/Infra에서 live 구현을 등록하기 전까지는 no-op
    }
}

