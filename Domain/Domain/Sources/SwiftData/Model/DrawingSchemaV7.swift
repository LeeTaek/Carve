//
//  DrawingSchemaV7.swift
//  Domain
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import SwiftData

/// 필사책(2.2 「회차별 필사책」)의 메타데이터를 위한 **additive only** 스키마.
///
/// ## 왜 V7 인가
///
/// 필사책 이름 · 완료 표시 · 만든 시각은 잉크 행에 둘 수 없다 — 필사책마다 한 번만 있는 값이고, 기존 필사 행(`BibleDrawing`)에 열을 더하면
/// 옛 앱이 그 열을 모른 채 기본값으로 채워 되올린다(혼재 버전 규칙 ②). 그래서 새 엔티티 `DrawingNotebook` 하나만 더한다.
/// 잉크 행은 `BibleDrawing` 그대로이고 필사책은 행의 `titleName` 접두로 가른다(`StoredBookKey`, 결정 1).
///
/// V6 의 다섯 엔티티(`BibleDrawing` · `BiblePageDrawing` · `FavoriteVerse` · `VerseDrawingVersion` · `DrawingEraseEpoch`)는
/// **형태를 바꾸지 않고 그대로 싣는다** — 같은 클래스를 다시 쓴다. 그래서 V6 → V7 은 lightweight migration 이고 필사 행은 한 필드도 건드리지 않는다.
///
/// ## 구버전과의 관계
///
/// 옛 앱은 모르는 레코드 타입(`CD_DrawingNotebook`)을 건너뛴다 — 1.3.0 에서 `CD_VerseDrawingVersion` · `CD_DrawingEraseEpoch` 로 실측했다(ENT-P1).
/// 2.0.0 · 2.1 이 이 타입을 건너뛰는지는 **출시 전에 실측한다**(plan 출시 관문 G). 옛 앱은 필사책 이름을 모르고 접두 행도 보지 못한다 —
/// 처음부터 있던 필사책(기본 필사책)만 보인다(결정 14 의 옛 기기 안내).
///
/// ## CloudKit 제약
///
/// 필드는 **전부 optional** 이고 unique 제약 · 관계가 없다(CloudKit private DB 미러링 요구). unique 가 없으므로 같은 `notebookID` 가
/// 물리 레코드 둘로 생길 수 있다 — 읽을 때 `updatedAt` 최신을 쓴다. 상태는 열거형 열이 아니라 String 이다(혼재 버전 규칙 ④ — `NotebookStatus(stored:)`).
///
/// - Important: **운영 컨테이너에 `CD_DrawingNotebook` 레코드 타입을 배포해야 동기화된다.** 배포한 타입은 Production 에서 지울 수 없다.
///              배포는 이 DAG 밖이다(plan 출시 관문 G-3).
/// - Important: forward-only 다. V7 로 마이그레이션된 저장소는 V6 빌드로 열 수 없다 — V6 빌드는 이 저장소를
///              "모르는 저장소" 로 가려 막는다(MIG-F1). **TestFlight 에 한 번 나간 뒤에는 필드를 고치지 말고 V8 로 올린다.**
///              말씀 카드 엔티티가 합류하면 첫 TestFlight 전에 이 V7 에 더한다(plan 결정 2) — 그 밖에는 V7 필드를 바꾸지 않는다.
/// - Important: C14 소유 증명 판독기(`LegacyRowLinkageReader.validatedSchemaMajors`)는 아직 V3 · V6 만 검증했다. V7 저장소는
///              「알 수 없음(unvalidatedModel)」 으로 판정돼 첫 로그인 · 계정 전환 · 1.3.0 업그레이드 증명이 보류(실패 닫힘)된다 —
///              검증 범위 확장은 사람 관측 뒤 별도 작업이다(plan G-2).
public enum DrawingSchemaV7: VersionedSchema {
    public static let versionIdentifier = Schema.Version(7, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            DrawingSchemaV4.BibleDrawing.self,
            DrawingSchemaV4.BiblePageDrawing.self,
            DrawingSchemaV6.FavoriteVerse.self,
            DrawingSchemaV6.VerseDrawingVersion.self,
            DrawingSchemaV6.DrawingEraseEpoch.self,
            DrawingNotebook.self
        ]
    }

    /// 필사책 하나의 메타데이터 — 이름 · 상태 · 시각과 예약 필드.
    ///
    /// 잉크는 담지 않는다. 메타데이터가 없어도 행이 있으면 필사책이다(혼재 버전 규칙 ⑥). 기본 필사책의 레코드는 이름을 바꾸거나
    /// 완료를 표시할 때만 `notebookID == "default"` 로 생긴다.
    @Model
    public final class DrawingNotebook {
        /// `NotebookID.rawValue` — `"default"` 또는 소문자 16진 32자리. 읽을 때 `NotebookID(rawValue:)` 로 검사한다.
        public var notebookID: String?
        /// 사용자가 붙인 이름. nil 이면 화면이 기본 이름을 보인다.
        public var name: String?
        /// `NotebookStatus.rawValue` — 열거형 열이 아니다. 모르는 값은 `active` 로 읽는다.
        public var status: String?
        /// 만든 시각.
        public var createdAt: Date?
        /// 이름 · 상태를 바꾼 시각 — 같은 `notebookID` 레코드가 둘이면 최신을 쓴다.
        public var updatedAt: Date?
        /// 완료를 표시한 시각. 완료를 취소하면 nil.
        public var completedAt: Date?
        /// 필사책 종류 — `"personal"`. 그룹 · 챌린지와 잇는 고리이고 1차는 늘 `"personal"` 이다.
        public var kind: String?
        /// 예약 — 말씀 범위 JSON. 1차는 nil(결정 4: 필사책 범위는 성경 전체).
        public var scopeData: String?
        /// 예약 — 그룹 · 챌린지 연결 JSON. 1차는 nil.
        public var linkData: String?

        public init() { }
    }
}

// MARK: - 현재 스키마 별칭

/// 앱 코드가 쓰는 **현재 스키마**의 필사책 메타데이터 모델.
public typealias DrawingNotebook = DrawingSchemaV7.DrawingNotebook

/// 앱이 저장소를 여는 스키마 — **현재 스키마 버전의 모델 전체**다.
///
/// 저장소를 여는 곳은 모두 이것을 쓴다. 모델 일부만 주면 마이그레이션 플랜의 마지막 버전과 맞지 않아 열리지 않거나,
/// 시험이 앱과 다른 스키마를 검증하게 된다. 2026-10-15 V6 → V7 로 올렸다(필사책 메타데이터).
public enum AppStoreSchema {
    public static var models: [any PersistentModel.Type] { DrawingSchemaV7.models }
    public static var schema: Schema { Schema(models) }
}
