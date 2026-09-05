//
//  DrawingSchemaV4.swift
//  Domain
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import SwiftData

/// 단일 Canvas 설계 §10-1 의 **additive only** 스키마.
///
/// V3 에서 **필드를 지우거나 의미를 바꾸지 않습니다.** 두 개의 optional 필드만 추가합니다.
///
/// | 추가 필드 | 용도 | 설계 |
/// |---|---|---|
/// | `layoutMetadataData` | `DrawingLayoutMetadata` Codable blob | §10-1 |
/// | `rowUUID` | 행 식별자. **신규 행에만** 발급 | §8-7 |
///
/// ## 이 스키마가 하지 않는 것 ★
///
/// - **좌표 변환을 하지 않습니다.** 레거시 판별은 verse rect 가 있어야 가능한데
///   migration 시점에는 레이아웃이 없습니다 (§10-2). 판별은 `ChapterLayout` 이 완성된
///   **런타임 이후**에 수행하며, 그 결과로 원본을 자동으로 덮어쓰지 않습니다.
/// - **`drawingVersion` 을 건드리지 않습니다.** 기존 행은 `1` 인 채로 남습니다
///   (§20-3 D8 실측: 실기기 225행 전부 `1`).
/// - **legacy 행에 `rowUUID` 를 소급 발급하지 않습니다.** 두 기기가 서로 다른 UUID 를
///   부여할 수 있고, 단순 조회가 쓰기를 유발해 비파괴 원칙(§9-4)을 깨기 때문입니다.
///
/// ## CloudKit 제약
///
/// 추가 필드는 **전부 optional** 이며 unique 제약이 없습니다 (CloudKit private DB 미러링 요구).
/// 따라서 V3 → V4 는 lightweight migration 으로 처리됩니다.
///
/// - Important: **forward-only 입니다 (§10-3).** V4 로 마이그레이션된 store 는 V3 빌드로
///              되돌릴 수 없습니다. 되돌릴 수단은 feature flag off 뿐이며, 그때도 저장소는
///              V4 인 채로 남습니다. 그래서 "기존 N Canvas 경로가 V4 저장소에서 동작하는지" 를
///              Phase 1 에서 먼저 확보합니다.
public enum DrawingSchemaV4: VersionedSchema {
    public static var versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [BibleDrawing.self, BiblePageDrawing.self]
    }

    /// 각 절에 해당하는 필사 데이터용 모델
    @Model
    public final class BibleDrawing: Equatable {
        public static func == (lhs: BibleDrawing, rhs: BibleDrawing) -> Bool {
            (lhs.id == rhs.id)
        }
        public var id: String!
        public var titleName: String?
        public var titleChapter: Int?
        public var verse: Int?
        public var creationDate: Date?
        public var updateDate: Date?
        public var translation: Translation? = Translation.NKRV

        /// **좌표 형식의 단일 진실** (설계 §5 · §10-1). V3 에서 이미 존재하던 필드이며,
        /// V4 는 새로 만들지 않고 **의미만 확정**합니다.
        ///
        /// | 값 | 의미 |
        /// |---|---|
        /// | `nil` / `1` | legacy. 좌표 형식 미확정 (절대좌표일 수도, 절 로컬일 수도 있음) |
        /// | `2` | verse local + `writingRect` **top-left** 기준 |
        /// | `3` | verse local + **첫 밑줄** 기준 + `layoutMetadataData` 동반 |
        ///
        /// - Important: 좌표 버전은 **이 필드 한 곳에만** 둡니다. DTO 나
        ///              `DrawingLayoutMetadata` 에 중복 저장하지 않습니다 (§10-1).
        ///              `DrawingLayoutMetadata.metadataSchemaVersion` 은 blob 자체의
        ///              인코딩 버전일 뿐 좌표 형식이 아닙니다.
        /// - Note: 값을 `3` 으로 올리는 것은 **해당 절을 실제로 편집해 저장할 때뿐**입니다
        ///         (§10-2 런타임 lazy 정책 5번). 마이그레이션이나 단순 조회는 올리지 않습니다.
        public var drawingVersion: Int? = 1
        public var isPresent: Bool? = false
        @Attribute(.externalStorage) public var lineData: Data?

        /// 저장 시점 레이아웃을 재현하기 위한 `DrawingLayoutMetadata` 의 Codable blob (§10-1).
        ///
        /// `drawingVersion == 3` 일 때 존재합니다. 그 밖의 값에서는 `nil` 이며,
        /// **`nil` 인 것 자체가 legacy 표식은 아닙니다** — 표식은 `drawingVersion` 입니다.
        ///
        /// - Note: 인코딩/디코딩 책임은 이 스키마에 없습니다. `DrawingLayoutMetadata` 는
        ///         SwiftData 를 알지 못하는 순수 DTO 이고, blob 변환은 저장 경로(Phase 3)에서 합니다.
        @Attribute(.externalStorage) public var layoutMetadataData: Data?

        /// 행 식별자 (§8-7). **신규 행 생성 시에만** 발급합니다.
        ///
        /// 기존 `id` 는 `"\(title).\(chapter).\(verse).\(Int(timestamp))"` 로 **초 단위**라
        /// 두 기기가 같은 초에 같은 절의 행을 만들면 충돌할 수 있습니다. 그래서 신규 행부터
        /// UUID 를 씁니다.
        ///
        /// | 대상 | 정책 |
        /// |---|---|
        /// | 신규 V4 행 | 생성 시 UUID 발급 |
        /// | 기존 legacy 행 | `nil` 유지. business `id` 를 그대로 row key 로 사용. **쓰기 갱신 없음** |
        ///
        /// - Important: Phase 3 은 저장 **전에** rowID 를 발급해 pending 큐의 키로 씁니다(§8-7).
        ///              그 경로에서는 반드시 **선발급한 값을 `rowUUID` 인자로 넘겨야** 하며,
        ///              기본값 생성에 맡기면 큐 키와 행의 값이 어긋납니다.
        public var rowUUID: String?

        public init() { }

        /// - Parameters:
        ///   - bibleTitle: 성경 이름과 장.
        ///   - verse: 절 번호.
        ///   - lineData: `PKDrawing.dataRepresentation()`.
        ///   - updateDate: 갱신 일시.
        ///   - layoutMetadataData: `DrawingLayoutMetadata` blob. 좌표 형식이 `3` 일 때만 의미가 있습니다.
        ///   - rowUUID: 행 식별자(§8-7). **선발급한 값이 있으면 반드시 그 값을 넘깁니다.**
        ///     기본값은 새 UUID 이므로 이 이니셜라이저로 만든 행은 항상 신규 행 취급입니다.
        public init(bibleTitle: BibleChapter,
                    verse: Int,
                    lineData: Data? = nil,
                    updateDate: Date? = Date.now,
                    layoutMetadataData: Data? = nil,
                    rowUUID: String? = UUID().uuidString
        ) {
            self.lineData = lineData
            self.titleName = bibleTitle.title.rawValue
            self.titleChapter = bibleTitle.chapter
            self.verse = verse
            self.creationDate = Date()
            self.updateDate = updateDate
            self.layoutMetadataData = layoutMetadataData
            self.rowUUID = rowUUID
            self.id = {
                if let timestamp = creationDate?.timeIntervalSince1970 {
                    return "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse).\(Int(timestamp))"
                } else {
                    return "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse).\(Date().timeIntervalSince1970)"
                }
            }()
        }

        public convenience init(bibleTitle: BibleChapter,
                                section: Int,
                                lineData: Data? = nil,
                                updateDate: Date? = Date.now
        ) {
            self.init(bibleTitle: bibleTitle, verse: section, lineData: lineData, updateDate: updateDate)
        }
    }

    /// 장에 해당하는 화면 전체 필사 데이터용 모델
    ///
    /// - Warning: **기준 데이터가 아닙니다** (§10-4). 동일 레이아웃에서만 유효한 캐시/복구용이며,
    ///            장 전체가 레코드 1개라 CloudKit 충돌 시 last-writer-wins 로 통째 덮어씁니다.
    ///            §20-3 D8 실측에서 실기기 `ZBIBLEPAGEDRAWING` 은 **0행**이었으므로 제거해도
    ///            마이그레이션 부담이 없지만, **제거는 Phase 1 의 범위가 아닙니다.**
    ///            V4 는 additive only 이므로 형태를 그대로 유지합니다.
    @Model
    public final class BiblePageDrawing: Equatable {

        public var id: String!
        public var titleName: String?
        public var titleChapter: Int?
        public var creationDate: Date?
        public var updateDate: Date?
        public var translation: Translation? = Translation.NKRV

        @Attribute(.externalStorage)
        public var fullLineData: Data?   // full PKDrawing

        public init() {}

        public init(
            bibleTitle: BibleChapter,
            fullLineData: Data?,
            updateDate: Date? = .now
        ) {
            self.titleName = bibleTitle.title.rawValue
            self.titleChapter = bibleTitle.chapter
            self.fullLineData = fullLineData
            self.creationDate = .now
            self.updateDate = updateDate
            self.id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter)"
        }
    }
}

// MARK: - 현재 스키마 별칭

/// 앱 코드가 쓰는 **현재 스키마**의 절 단위 필사 모델.
///
/// 스키마 구성(`ModelContainer`), `DrawingDatabase`, Feature 계층이 모두 이 별칭을 경유하므로
/// 버전 승격은 여기 한 줄만 바꾸면 전파됩니다.
public typealias BibleDrawing = DrawingSchemaV4.BibleDrawing
/// 앱 코드가 쓰는 **현재 스키마**의 장 단위 필사 모델. 격하 사유는 §10-4 참조.
public typealias BiblePageDrawing = DrawingSchemaV4.BiblePageDrawing

extension Array where Element == BibleDrawing {
    /// 여러 BibleDrawing 중 메인 Drawing 하나를 선택 — **결정적 규칙** (설계 §8-7, Phase 3).
    ///
    /// 1. `isPresent == true` 인 행들 중 `updateDate` 최신
    /// 2. 동률이면 행 키(`rowUUID` 또는 business `id`) 사전순
    /// 3. `isPresent` 행이 없으면 `updateDate` 최신 → 동률이면 행 키 사전순
    ///
    /// 이전 구현은 `first(where: isPresent)` 라 배열 순서에 의존했다. CloudKit 충돌로 `isPresent == true` 가
    /// 둘 이상이면 실행마다 대표가 달라질 수 있었으므로 `DrawingRepresentativeRule` 로 고정한다.
    /// `isPresent` 행이 하나뿐인 보통의 경우 결과는 이전과 같다.
    public func mainDrawing() -> BibleDrawing? {
        DrawingRepresentativeRule.pick(self)
    }
}
