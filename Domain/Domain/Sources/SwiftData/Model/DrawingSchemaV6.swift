//
//  DrawingSchemaV6.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import SwiftData

/// 절 필기의 **불변 버전**과 **전체 삭제 기준점**을 위한 additive 스키마 (정책 §5 · §12-5 · §12-6).
///
/// V5 의 필사 행(`BibleDrawing`) · 구 구조 행(`BiblePageDrawing`)은 **형태를 바꾸지 않고 그대로 싣는다.** 2.0.0 은
/// `BibleDrawing` 에 쓰지 않는다(C9) — legacy 행은 1.3.0 과 주고받는 원본이고, 2.0.0 의 편집은 새 엔티티
/// `VerseDrawingVersion` 에 버전으로 쌓는다. 즐겨찾기에는 삭제 기준점 집합(`K`) 하나를 더한다(S9).
///
/// ## 구버전과의 관계 (ENT-P1 · F19 ~ F21)
///
/// 1.3.0 은 모르는 레코드 타입(`CD_VerseDrawingVersion` · `CD_DrawingEraseEpoch`)을 건너뛰고, 그 기기를 새 스키마로 올리면
/// 건너뛴 레코드를 받는다. 1.3.0 의 전체 삭제는 `CD_BibleDrawing` 만 지운다. 기준점 엔티티는 그 시험에 없었으므로
/// **운영 배포 전에 이 스키마 그대로 다시 확인한다**(C13).
///
/// ## CloudKit 제약
///
/// 필드는 **전부 optional 이거나 기본값이 있고**, unique 제약 · 관계가 없다(CloudKit private DB 미러링 요구).
/// unique 가 없으므로 같은 논리 버전이 물리 레코드 둘로 생길 수 있다 — 읽을 때 `versionID` 로 합친다(C5).
///
/// - Important: **운영 컨테이너에 두 레코드 타입을 배포해야 동기화된다.** 배포한 타입은 Production 에서 지울 수 없다.
/// - Important: forward-only 다. V6 로 마이그레이션된 저장소는 V5 빌드로 열 수 없다 — V5 빌드는 이 저장소를
///              "모르는 저장소" 로 가려 막는다(MIG-F1). **TestFlight 에 한 번 나간 뒤에는 필드를 고치지 말고 V7 로 올린다.**
public enum DrawingSchemaV6: VersionedSchema {
    public static var versionIdentifier = Schema.Version(6, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            DrawingSchemaV4.BibleDrawing.self,
            DrawingSchemaV4.BiblePageDrawing.self,
            FavoriteVerse.self,
            VerseDrawingVersion.self,
            DrawingEraseEpoch.self
        ]
    }

    /// 즐겨찾기한 절 하나 — V5 와 같고 삭제 기준점 집합만 더했다.
    @Model
    public final class FavoriteVerse {
        public var favoriteID: String?
        public var titleName: String?
        public var titleChapter: Int?
        public var verse: Int?
        public var translation: Translation? = Translation.NKRV
        public var createdDate: Date?
        public var sentence: String?
        @Attribute(.externalStorage) public var lineData: Data?
        /// 추가할 때 알던 삭제 기준점 집합 `K(x)` — 정렬한 JSON 배열. `nil` 은 빈 집합이다(V5 에서 올라온 행).
        public var knownEraseEpochs: String?

        public init() { }

        public init(
            chapter: BibleChapter,
            verse: Int,
            translation: Translation,
            sentence: String,
            lineData: Data?,
            createdDate: Date,
            favoriteID: String = UUID().uuidString,
            knownEraseEpochs: Set<String> = []
        ) {
            self.favoriteID = favoriteID
            self.titleName = chapter.title.rawValue
            self.titleChapter = chapter.chapter
            self.verse = verse
            self.translation = translation
            self.sentence = sentence
            self.lineData = lineData
            self.createdDate = createdDate
            self.knownEraseEpochs = EraseEpochSetCoding.encode(knownEraseEpochs)
        }
    }

    /// 절 필기의 불변 버전 하나 (정책 §12-5 C1 · §12-6).
    ///
    /// 만든 뒤에는 고치지 않는다. 편집 · 선택 · 지우기 · legacy 수용은 모두 **새 버전**이고, 이전 버전은 `parentIDs` 로 잇는다.
    @Model
    public final class VerseDrawingVersion {
        /// 논리 ID. 사용자 버전은 UUID, legacy 수용은 결정적 ID(C3 ⑤)다. 물리 레코드가 둘이어도 같은 ID 면 하나로 다룬다.
        public var versionID: String?
        /// `VerseDrawingVersionKind` 의 원시값.
        public var kind: String?
        public var translation: Translation? = Translation.NKRV
        public var titleName: String?
        public var titleChapter: Int?
        public var verse: Int?
        /// 이 버전이 이어받은(확인한) 버전들 — 정렬한 JSON 배열. 분기 선택은 묶음에 든 후보 ID 를 모두 적는다(C7).
        public var parentIDs: String?
        @Attribute(.externalStorage) public var lineData: Data?
        /// 좌표 형식. `BibleDrawing.drawingVersion` 과 같은 뜻이다(1 · 2 · 3).
        public var drawingVersion: Int?
        @Attribute(.externalStorage) public var layoutMetadataData: Data?
        /// `VerseContentFingerprint` — 같은 논리 ID 인데 내용이 다르면 무결성 오류로 다룬다(C5).
        public var contentFingerprint: String?
        /// 만들 때 알던 삭제 기준점 집합 `K(x)` — 정렬한 JSON 배열. 일반 편집은 초안의 `K` 를 잇는다(§12-6 C11).
        public var knownEraseEpochs: String?
        /// legacy 수용이면 원본을 가리키는 값(진단용 JSON). 판정에 쓰지 않는다.
        public var legacySource: String?
        /// 사용자가 확정한 시각(표시용). **순서 판정에 쓰지 않는다** — 기기 시계가 다를 수 있다(§8).
        public var authoredAt: Date?
        public var createdAt: Date?
        /// 만든 설치의 ID.
        public var deviceID: String?

        public init() { }
    }

    /// 전체 삭제 기준점 (정책 §12-6 C11). **추가만 하고 지우지 않는다.** 동시에 만든 기준점은 모두 유효하다.
    @Model
    public final class DrawingEraseEpoch {
        /// 삭제 작업을 시작할 때 미리 정한 ID — 재시도해도 기준점이 늘지 않는다.
        public var epochID: String?
        /// 만들 때 알던 기준점 집합(이전 기준점의 집합까지 펼친 닫힌 집합) — 정렬한 JSON 배열.
        public var knownEraseEpochs: String?
        public var deviceID: String?
        /// 표시용 시각. 판정에 쓰지 않는다.
        public var createdAt: Date?

        public init() { }

        public init(epochID: String, knownEraseEpochs: Set<String>, deviceID: String, createdAt: Date) {
            self.epochID = epochID
            self.knownEraseEpochs = EraseEpochSetCoding.encode(knownEraseEpochs)
            self.deviceID = deviceID
            self.createdAt = createdAt
        }
    }
}

/// 버전의 종류 (정책 §12-6 용어).
public enum VerseDrawingVersionKind: String, Codable, CaseIterable, Sendable {
    /// 사용자가 편집해 확정했다.
    case edit
    /// 분기 안내에서 하나를 골랐다.
    case select
    /// 절을 지웠다.
    case clear
    /// legacy 원본을 수용했다(C3 ④). 의도적 버전이 아니다.
    case legacyImport
    /// legacy 삭제 관측을 수용했다. 의도적 버전이 아니다.
    case legacyDelete

    /// 사용자가 한 결정인가. `legacyImport` 만 있는 절은 "의도적 버전 없음" 으로 본다(C7).
    public var isIntentional: Bool {
        switch self {
        case .edit, .select, .clear: true
        case .legacyImport, .legacyDelete: false
        }
    }
}

/// 문자열 필드에 담는 ID 집합의 형식. **정렬한 JSON 배열**이다 — 같은 집합이면 같은 문자열이 나와야 레코드를 비교할 수 있다.
public enum EraseEpochSetCoding {
    public static func encode(_ ids: Set<String>) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(ids.sorted()) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// `nil` · 빈 문자열은 빈 집합이다. 읽지 못하는 값도 빈 집합으로 두지 않고 `nil` 을 돌려준다 —
    /// 알 수 없는 `K` 를 "아무 삭제도 몰랐다" 로 읽으면 판정이 바뀐다.
    public static func decode(_ text: String?) -> Set<String>? {
        guard let text, !text.isEmpty else { return [] }
        guard let data = text.data(using: .utf8), let ids = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return Set(ids)
    }
}

// MARK: - 현재 스키마 별칭

/// 앱 코드가 쓰는 **현재 스키마**의 즐겨찾기 모델.
public typealias FavoriteVerse = DrawingSchemaV6.FavoriteVerse
/// 앱 코드가 쓰는 **현재 스키마**의 절 필기 버전 모델.
public typealias VerseDrawingVersion = DrawingSchemaV6.VerseDrawingVersion
/// 앱 코드가 쓰는 **현재 스키마**의 전체 삭제 기준점 모델.
public typealias DrawingEraseEpoch = DrawingSchemaV6.DrawingEraseEpoch

/// 앱이 저장소를 여는 스키마 — **현재 스키마 버전의 모델 전체**다.
///
/// 저장소를 여는 곳은 모두 이것을 쓴다. 모델 일부만 주면 마이그레이션 플랜의 마지막 버전과 맞지 않아 열리지 않거나,
/// 시험이 앱과 다른 스키마를 검증하게 된다.
public enum AppStoreSchema {
    public static var models: [any PersistentModel.Type] { DrawingSchemaV6.models }
    public static var schema: Schema { Schema(models) }
}
