//
//  BackupItem.swift
//  Domain
//
//  Created by Claude on 10/2/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

/// `items.json` 의 항목 하나 — `BibleDrawing` 행 하나 또는 저장소에 반영되지 않은 초안 하나 (설계 §2-4).
///
/// 바이트(잉크 · 메타데이터)는 JSON 에 넣지 않고 blob 이름으로 가리킨다. 모든 값은 **원본 그대로**다 — `drawingVersion` 을 승격 · 강등하지 않고,
/// 번역 저장값이 없으면 NKRV 로 채우지 않는다. Optional 은 nil 이면 키가 빠지고, 읽을 때 키 없음과 `null` 을 같게 nil 로 읽는다.
public struct BackupItem: Codable, Equatable, Sendable {
    /// 파일 안 항목 이름(`BackupItemID.make` — `row-<hex>` · `draft-<hex>`). 불러오기의 중복 판정은 id 가 아니라 `fingerprint` 로 한다.
    public var id: String
    /// 행인가 초안인가.
    public var kind: BackupItemKind
    /// V6 계보의 자리. formatVersion 1 은 늘 `[]` 다.
    public var parents: [String]
    /// 번역본 · 권 · 장 · 절.
    public var verse: BackupVerseKey
    /// 좌표 형식 원본(nil · 1 · 2 · 3).
    public var drawingVersion: Int?
    /// `lineData` 원본 바이트의 blob 이름. 비운 행이면 nil.
    public var inkBlob: String?
    /// `layoutMetadataData` 원본 바이트의 blob 이름. 비운 행에도 남아 있으면 담는다.
    public var metadataBlob: String?
    /// 잉크가 있을 때만 `VerseContentFingerprint.make(lineData:drawingVersion:layoutMetadataBlob:)` — 원본 바이트로. 비운 항목은 nil.
    public var fingerprint: String?
    /// 행: 그 절의 `DrawingRepresentativeRule` 대표(비운 대표 포함 — 그 절에 shown 초안이 있으면 false). 초안: 분류가 shown 일 때만 true.
    public var isCurrent: Bool
    /// 행: `creationDate` 원본. 초안: nil.
    public var createdAt: Date?
    /// 행: `updateDate` 원본. 초안: 초안을 남긴 시각(`savedAt`).
    public var updatedAt: Date?
    /// 원본 위치 · 출처.
    public var source: BackupItemSource

    /// 항목을 만든다.
    public init(
        id: String,
        kind: BackupItemKind,
        parents: [String] = [],
        verse: BackupVerseKey,
        drawingVersion: Int?,
        inkBlob: String?,
        metadataBlob: String?,
        fingerprint: String?,
        isCurrent: Bool,
        createdAt: Date?,
        updatedAt: Date?,
        source: BackupItemSource
    ) {
        self.id = id
        self.kind = kind
        self.parents = parents
        self.verse = verse
        self.drawingVersion = drawingVersion
        self.inkBlob = inkBlob
        self.metadataBlob = metadataBlob
        self.fingerprint = fingerprint
        self.isCurrent = isCurrent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
    }

    /// 잉크가 있는 항목인가 — 없으면 비운 항목(판정기의 「비운 항목」 규칙).
    public var hasInk: Bool { inkBlob != nil }
}

/// 항목의 종류 (설계 §2-4).
public enum BackupItemKind: String, Codable, Sendable, CaseIterable {
    /// `BibleDrawing` 행.
    case row
    /// 저장소에 반영되지 않은 초안.
    case draft
}

/// 절 식별 — 번역본 저장값 + USFM 권 코드 + 장 · 절 (설계 §2-4, 결정 9).
public struct BackupVerseKey: Codable, Equatable, Hashable, Sendable {
    /// 행 · 초안에 저장된 번역본 값 그대로(`Translation.rawValue`). 없으면 nil — NKRV 로 채우지 않는다.
    public var translation: String?
    /// USFM 권 코드(`GEN` … `REV`). 모르는 코드도 그대로 읽고, 지원 판정(`BackupItemSupport`)이 건너뛴다.
    public var book: String
    /// 장.
    public var chapter: Int
    /// 절.
    public var verse: Int

    /// 값을 그대로 지정해 만든다.
    public init(translation: String?, book: String, chapter: Int, verse: Int) {
        self.translation = translation
        self.book = book
        self.chapter = chapter
        self.verse = verse
    }

    /// `BibleTitle` 에서 권 코드를 찾아 만든다 — 내보내기의 단일 진입점.
    public init(translation: String?, title: BibleTitle, chapter: Int, verse: Int) {
        self.init(translation: translation, book: BibleBookCode(title: title).rawValue, chapter: chapter, verse: verse)
    }

    /// 권 코드가 가리키는 권. 모르는 코드면 nil.
    public var title: BibleTitle? {
        BibleBookCode(rawValue: book)?.title
    }
}

/// 항목의 원본 출처 (설계 §2-4).
public struct BackupItemSource: Codable, Equatable, Sendable {
    /// 초안 묶음 — `draftScope` 에 쓰는 값. **계정 해시는 넣지 않는다.**
    public enum DraftScope: String, Codable, Sendable, CaseIterable {
        /// 로그인하지 않은 동안의 묶음(`acct-local`).
        case local
        /// 계정을 확인하지 못한 동안의 묶음(`acct-unverified`).
        case unverified
        /// 확인된 계정 묶음.
        case account
    }

    /// `BibleTitle.rawValue` 원문(예: `1-01Genesis.txt`) — 권 코드와 함께 원본을 보존한다.
    public var titleName: String
    /// 행: `rowUUID ?? business id`. 초안: 식별 · 판정에 쓰지 않는다(nil 이어도 된다).
    public var rowKey: String?
    /// 초안만: `DraftScope` 의 원시값(`"local"` · `"unverified"` · `"account"`).
    public var draftScope: String?
    /// 초안만: 그 세션 · 절의 revision.
    public var draftRevision: Int?

    /// 출처를 만든다.
    public init(titleName: String, rowKey: String? = nil, draftScope: String? = nil, draftRevision: Int? = nil) {
        self.titleName = titleName
        self.rowKey = rowKey
        self.draftScope = draftScope
        self.draftRevision = draftRevision
    }
}
