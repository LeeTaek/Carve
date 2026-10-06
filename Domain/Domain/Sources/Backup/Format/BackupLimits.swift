//
//  BackupLimits.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 백업 파일의 상한 (설계 §2-8). 넘으면 **저장소를 바꾸기 전에** 거부한다.
///
/// 풀기(`BackupArchive.read`)는 이 타입을 모르고 원시 값(`archiveEntryLimit` · `maxTotalBytes`)만 받는다.
/// 초기값은 실측으로 조정한다 — 참고 규모: 실사용 계정 271행 · 잉크 평균 15.3 KB · 최대 111 KB(정책 §3-2).
public struct BackupLimits: Codable, Equatable, Sendable {
    /// blob 하나의 최대 바이트 수(초기 64 MB).
    public var maxBlobBytes: Int
    /// 풀린 합계의 최대 바이트 수(초기 4 GB).
    public var maxTotalBytes: Int
    /// 항목(`items.json`) 최대 수(초기 200,000).
    public var maxItems: Int
    /// `manifest.json` · `items.json` 각각의 최대 바이트 수(초기 128 MB). 항목 200,000 이면 `items.json` 이 blob 상한(64 MB)을 넘을 수 있다.
    public var maxIndexBytes: Int

    /// 상한을 만든다. 인자를 빼면 초기값이다.
    public init(
        maxBlobBytes: Int = 64 * 1024 * 1024,
        maxTotalBytes: Int = 4 * 1024 * 1024 * 1024,
        maxItems: Int = 200_000,
        maxIndexBytes: Int = 128 * 1024 * 1024
    ) {
        self.maxBlobBytes = maxBlobBytes
        self.maxTotalBytes = maxTotalBytes
        self.maxItems = maxItems
        self.maxIndexBytes = maxIndexBytes
    }

    /// 풀기(`BackupArchive.read` 의 `maxEntryBytes`)에 넘길 항목 하나의 상한 — blob 과 색인 파일 중 큰 쪽.
    ///
    /// 컨테이너는 항목 이름으로 종류를 가리지 않으므로 blob 상한을 그대로 쓰면 큰 `items.json` 을 풀지 못한다.
    /// 종류별 상한(blob 64 MB · 색인 128 MB)은 검증기가 따로 본다.
    public var archiveEntryLimit: Int {
        max(maxBlobBytes, maxIndexBytes)
    }

    /// 초기값.
    public static let `default` = BackupLimits()
}
