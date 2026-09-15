//
//  SentenceSettingBackup.swift
//  Domain
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

/// iCloud 에 백업하는 본문 모양 — 본문 설정에서 사용자가 고르는 네 항목(글꼴 · 글자 크기 · 줄 간격 · 자간).
///
/// 줄 수 · 기준 줄 높이처럼 사용자가 고르지 않는 값은 담지 않는다. 되살릴 때는 기기에 저장된 설정 위에 네 항목만 덮는다.
/// 항목을 더해도 이전 빌드는 모르는 키를 무시하고 읽는다. 뜻이 바뀌면 `SentenceSettingCloudBackup.cloudKey` 를 새로 만든다.
public struct SentenceSettingBackup: Codable, Equatable, Sendable {
    /// 본문 글꼴.
    public var fontFamily: FontCase
    /// 글자 크기.
    public var fontSize: CGFloat
    /// 줄 간격.
    public var lineSpace: CGFloat
    /// 자간.
    public var traking: CGFloat

    /// `setting` 에서 사용자가 고르는 네 항목을 뽑는다.
    public init(_ setting: SentenceSetting) {
        fontFamily = setting.fontFamily
        fontSize = setting.fontSize
        lineSpace = setting.lineSpace
        traking = setting.traking
    }

    /// `setting` 에 네 항목을 덮은 값. 나머지 값은 `setting` 그대로다.
    public func applied(to setting: SentenceSetting) -> SentenceSetting {
        var setting = setting
        setting.fontFamily = fontFamily
        setting.fontSize = fontSize
        setting.lineSpace = lineSpace
        setting.traking = traking
        return setting
    }
}

/// 본문 모양 iCloud 백업 중 Feature 가 쓰는 쪽 — 사용자가 본문 설정에서 고른 값을 알린다.
///
/// 실행 때 되살리기는 App 이 만들어 시작한 `SentenceSettingCloudBackup` 이 맡고, 같은 인스턴스를 이 의존성으로 주입한다.
public protocol SentenceSettingBackupClient: Sendable {
    /// 사용자가 본문 모양을 바꿨다 — 이 설치를 「바꾼 설치」로 기록하고(이후 iCloud 값으로 덮지 않는다) 바뀐 값을 iCloud 에 올린다.
    func saveUserChoice(_ setting: SentenceSetting)
}

private enum SentenceSettingBackupClientKey: DependencyKey {
    // 실제 백업은 App 이 주입한다. 주입하지 않은 곳(미리보기 · 테스트)은 iCloud 에 쓰지 않는다.
    static let liveValue: any SentenceSettingBackupClient = NoopSentenceSettingBackupClient()
    static let testValue: any SentenceSettingBackupClient = NoopSentenceSettingBackupClient()
}

public extension DependencyValues {
    /// 본문 모양 iCloud 백업.
    var sentenceSettingBackup: any SentenceSettingBackupClient {
        get { self[SentenceSettingBackupClientKey.self] }
        set { self[SentenceSettingBackupClientKey.self] = newValue }
    }
}

/// 아무것도 올리지 않는 백업.
private struct NoopSentenceSettingBackupClient: SentenceSettingBackupClient {
    func saveUserChoice(_ setting: SentenceSetting) {}
}
