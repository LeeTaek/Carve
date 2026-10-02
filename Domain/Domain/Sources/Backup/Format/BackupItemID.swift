//
//  BackupItemID.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// 백업 항목 id (설계 §2-5).
///
/// ```
/// 정규 문자열 = ["carve.backupItem/1", kind, sourceKey, fingerprint ?? "empty"]
///               구성요소마다 "<UTF-8 바이트 길이>:<값>" 으로 바꿔 "|" 로 잇는다
/// id          = ("row-" | "draft-") + SHA-256(정규 문자열) 소문자 hex 64자
/// ```
///
/// `LegacyVersionID` 와 같은 방식(길이 접두로 경계를 고정 · 종류와 내용 지문을 넣는다)이고 이름공간만 다르다 —
/// 같은 행이 다른 내용이 되면 다른 id 다. id 는 **파일 안 항목의 이름**이고, 불러오기의 중복 판정은 내용 지문으로 한다.
public enum BackupItemID {
    /// 정규 문자열의 이름공간.
    public static let namespace = "carve.backupItem/1"
    /// 지문이 없는(비운) 항목의 지문 자리 값.
    public static let emptyFingerprint = "empty"

    /// 항목 id 를 만든다.
    /// - Parameters:
    ///   - kind: 행 · 초안.
    ///   - sourceKey: 행이면 `rowKey`(`rowUUID ?? business id`), 초안이면 `draftSourceKey(...)`.
    ///   - fingerprint: 잉크가 있을 때의 내용 지문. nil 이면 `"empty"` 로 넣는다.
    /// - Returns: `row-<hex64>` · `draft-<hex64>`. 부작용 없음.
    public static func make(kind: BackupItemKind, sourceKey: String, fingerprint: String?) -> String {
        "\(kind.rawValue)-" + BackupFormat.sha256Hex(Data(canonical(kind: kind, sourceKey: sourceKey, fingerprint: fingerprint).utf8))
    }

    /// 초안의 `sourceKey` — `"<draftScope>|<sessionID>|<translation>|<title>|<chapter>|<verse>|<revision>"`.
    /// - Parameters:
    ///   - draftScope: `BackupItemSource.DraftScope` 의 원시값(계정 해시가 아니다).
    ///   - sessionID · translation · title · chapter · verse: 초안 키(`VerseDraftKey`)의 값 그대로(`title` 은 `BibleTitle.rawValue`).
    ///   - revision: 초안의 revision.
    public static func draftSourceKey(
        draftScope: String,
        sessionID: String,
        translation: String,
        title: String,
        chapter: Int,
        verse: Int,
        revision: Int
    ) -> String {
        [draftScope, sessionID, translation, title, "\(chapter)", "\(verse)", "\(revision)"].joined(separator: "|")
    }

    /// 해시하기 전의 정규 문자열. 구성요소마다 UTF-8 길이를 앞에 붙여 경계를 고정한다 — 이어 붙인 문자열이 우연히 같아지는 것을 막는다.
    static func canonical(kind: BackupItemKind, sourceKey: String, fingerprint: String?) -> String {
        [namespace, kind.rawValue, sourceKey, fingerprint ?? emptyFingerprint]
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
    }
}
