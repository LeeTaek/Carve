//
//  Translation.swift
//  Domain
//
//  Created by 이택성 on 7/10/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

/// 성경 번역 버전
public enum Translation: String, Codable, Sendable {
    case NKRV       // 개역개정

    /// 화면에 적는 번역본 이름. 필사 화면 헤더 부제(`HeaderView`)와 같은 표기다.
    public var displayName: String {
        switch self {
        case .NKRV: "개역개정"
        }
    }
}
