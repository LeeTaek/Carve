//
//  DrawingSchemaV5.swift
//  Domain
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import SwiftData

/// 즐겨찾기(시안 N)를 위한 **additive only** 스키마.
///
/// V4 의 두 엔티티는 **형태를 바꾸지 않고 그대로 싣는다** — `DrawingSchemaV4.BibleDrawing` · `BiblePageDrawing` 클래스를
/// 다시 쓰고, 새 엔티티 `FavoriteVerse` 하나만 더한다. 그래서 V4 → V5 는 lightweight migration 이고
/// 필사 행(`BibleDrawing`)은 한 필드도 건드리지 않는다.
///
/// ## 보관 단위 (2026-09-15 결정)
///
/// 즐겨찾기는 **추가한 당시의 본문 · 필기를 복사해 보존한다.** 이후 원래 절을 지우거나 다시 써도 즐겨찾기의 필기는 그대로다.
/// 필사 행을 참조하지 않으므로 R27 · R28 의 행 식별 문제와 얽히지 않는다. 번역본 · 권 · 장 · 절마다 한 항목이다.
///
/// ## CloudKit 제약
///
/// 필드는 **전부 optional** 이고 unique 제약이 없다 (CloudKit private DB 미러링 요구).
/// unique 가 없으므로 두 기기가 같은 절을 따로 즐겨찾기하면 행이 둘 생길 수 있다 — 저장소가 키(번역본 · 권 · 장 · 절)로 합친다.
///
/// - Important: **CloudKit 운영 컨테이너에 `CD_FavoriteVerse` 레코드 타입을 배포해야 동기화된다.** Development 환경은
///              Debug 빌드가 처음 내보낼 때 자동으로 만들지만, Production 은 CloudKit Dashboard 에서 배포해야 하고
///              **배포한 타입은 Production 에서 지울 수 없다.**
/// - Important: forward-only 다 (V4 와 같다). V5 로 마이그레이션된 store 는 V4 빌드로 열 수 없다.
public enum DrawingSchemaV5: VersionedSchema {
    public static var versionIdentifier = Schema.Version(5, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [DrawingSchemaV4.BibleDrawing.self, DrawingSchemaV4.BiblePageDrawing.self, FavoriteVerse.self]
    }

    /// 즐겨찾기한 절 하나 — 추가한 당시의 본문과 필기를 담는다.
    @Model
    public final class FavoriteVerse {
        /// 행 식별자(UUID). 같은 절의 행이 여럿일 때 정렬을 결정적으로 만드는 데도 쓴다.
        public var favoriteID: String?
        /// `BibleTitle.rawValue` — `BibleDrawing.titleName` 과 같은 값이다.
        public var titleName: String?
        public var titleChapter: Int?
        public var verse: Int?
        public var translation: Translation? = Translation.NKRV
        /// 즐겨찾기에 추가한 시각. 목록은 이 값의 최신순이다.
        public var createdDate: Date?
        /// 추가한 당시의 본문.
        public var sentence: String?
        /// 추가한 당시의 필기(`PKDrawing.dataRepresentation()`). 획이 없던 절이면 nil.
        @Attribute(.externalStorage) public var lineData: Data?

        public init() { }

        public init(
            chapter: BibleChapter,
            verse: Int,
            translation: Translation,
            sentence: String,
            lineData: Data?,
            createdDate: Date,
            favoriteID: String = UUID().uuidString
        ) {
            self.favoriteID = favoriteID
            self.titleName = chapter.title.rawValue
            self.titleChapter = chapter.chapter
            self.verse = verse
            self.translation = translation
            self.sentence = sentence
            self.lineData = lineData
            self.createdDate = createdDate
        }
    }
}

// 현재 스키마 별칭(`FavoriteVerse`)은 V6 로 옮겼다 — `DrawingSchemaV6.swift`.
