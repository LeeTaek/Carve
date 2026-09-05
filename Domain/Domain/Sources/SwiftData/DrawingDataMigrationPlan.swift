//
//  DrawingDataMigrationPlan.swift
//  Domain
//
//  Created by 이택성 on 7/10/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import SwiftData
import PencilKit

/// 모델에 버전이 할당되지 않았을 경우(1.1.0 버전 이전) 사용하는 MigrationPlan
enum MigrationPlanV1Only: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] {
        [DrawingSchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }
}


/// BibleDrawing 관련 SwiftData Schema(V1~V4) 마이그레이션 플랜
/// V1 -> V2: DrawingVO -> BibleDrawing 모델명 및 속성 변경 (Custom)
/// V2 -> V3: BiblePageDrawing 추가(lightWeight)
/// V3 -> V4: optional 필드 2개 추가(lightWeight). **데이터 변환 없음** — 설계 §10-2
enum DrawingDataMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] {
        [DrawingSchemaV1.self, DrawingSchemaV2.self, DrawingSchemaV3.self, DrawingSchemaV4.self]
    }

    private static var updatedDrawings: [DrawingSchemaV2.BibleDrawing] = []

    static let migrationV1toV2 = MigrationStage.custom(
        fromVersion: DrawingSchemaV1.self,
        toVersion: DrawingSchemaV2.self,
        willMigrate: { context in
            /// 기존 V1 DrawingVO 전체를 로드한 뒤, 유효한 드로잉만 필터링하여 V2.BibleDrawing으로 매핑.
            let drawings = try context.fetch(FetchDescriptor<DrawingSchemaV1.DrawingVO>())
            updatedDrawings = drawings
                .filter { drawing in        // drawing이 비어있으면 제거
                    if drawing.lineData?.containsPKStroke == true {
                        return true
                    } else {
                        context.delete(drawing)
                        return false
                    }
                }
                .map { old in
                let new = DrawingSchemaV2.BibleDrawing()
                new.id = {
                    if let title = old.titleName,
                       let chapter = old.titleChapter,
                       let verse = old.section,
                       let createdAt = old.creationDate {
                        let timestamp = Int(createdAt.timeIntervalSince1970)
                        return "\(title).\(chapter).\(verse).\(timestamp)"
                    } else {
                        return old.id
                    }
                }()
                new.titleName = old.titleName
                new.titleChapter = old.titleChapter
                new.translation = .NKRV
                new.drawingVersion = 1
                new.verse = old.section
                new.creationDate = old.creationDate
                new.updateDate = old.updateDate
                new.lineData = old.lineData
                return new
            }
            try context.save()
        },
        didMigrate: { context in
            updatedDrawings.forEach { context.insert($0) }
            try context.save()
        }
    )
    
    /// BiblePageDrawing만 추가
    static let migrationV2toV3 = MigrationStage.lightweight(
        fromVersion: DrawingSchemaV2.self,
        toVersion: DrawingSchemaV3.self
    )

    /// `layoutMetadataData` · `rowUUID` optional 필드 2개만 추가 (설계 §10-1).
    ///
    /// ## 여기에 데이터 변환을 넣지 마십시오 ★ (설계 §10-2)
    ///
    /// 레거시 좌표 판별(`normalizedForVerseRect`)은 **현재 verse rect** 가 있어야 동작하는데,
    /// schema migration 시점에는 SwiftUI 레이아웃도 Canvas rect 도 존재하지 않습니다.
    /// 그래서 이 단계에서는 tolerance 휴리스틱을 실행할 수 없고, 실행해서도 안 됩니다.
    ///
    /// - `drawingVersion` 을 갱신하지 않습니다. 기존 행은 `1` 인 채로 남습니다
    ///   (§20-3 D8 실측: 실기기 225행 전부 `1`).
    /// - 좌표를 변환하지 않습니다. 판별은 `ChapterLayout` 이 완성된 **런타임 이후**에 하고,
    ///   결과로 원본을 자동으로 덮어쓰지 않습니다 (§10-2 정책 4번).
    /// - 그 판별은 일회성 배치가 아니라 **legacy 행을 만날 때마다 수행하는 런타임 경로**여야 합니다.
    ///   CloudKit 은 마이그레이션 이후에도 메타데이터 없는 행을 계속 실어 나릅니다.
    ///
    /// - Important: forward-only 입니다 (§10-3). 이 단계를 거친 store 는 V3 빌드로 열 수 없습니다.
    static let migrationV3toV4 = MigrationStage.lightweight(
        fromVersion: DrawingSchemaV3.self,
        toVersion: DrawingSchemaV4.self
    )

    /// 정의된 순서대로 마이그레이션 실행 (V1 -> V2, V2 -> V3, V3 -> V4)
    static var stages: [MigrationStage] {
        [
            migrationV1toV2,
            migrationV2toV3,
            migrationV3toV4
        ]
    }
}
