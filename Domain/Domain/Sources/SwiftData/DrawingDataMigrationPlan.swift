//
//  DrawingDataMigrationPlan.swift
//  Domain
//
//  Created by 이택성 on 7/10/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import SwiftData

import Dependencies

/// 모델에 버전이 할당되지 않았을 경우(1.1.0 버전 이전) 사용하는 MigrationPlan
enum MigrationPlanV1Only: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] {
        [DrawingSchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }
}

/// 사용자 정의 migration 경계를 넘길 값만 보관한다.
/// source context에서 destination SwiftData 모델을 만들면 iOS 17에서 아직 등록되지 않은 모델로 취급된다.
private struct V1DrawingMigrationValue: Sendable {
    let id: String?
    let titleName: String?
    let titleChapter: Int?
    let verse: Int?
    let creationDate: Date?
    let updateDate: Date?
    let lineData: Data?

    func makeV2Drawing() -> DrawingSchemaV2.BibleDrawing {
        let drawing = DrawingSchemaV2.BibleDrawing()
        drawing.id = id
        drawing.titleName = titleName
        drawing.titleChapter = titleChapter
        drawing.translation = .NKRV
        drawing.drawingVersion = 1
        drawing.verse = verse
        drawing.creationDate = creationDate
        drawing.updateDate = updateDate
        drawing.lineData = lineData
        return drawing
    }
}


/// BibleDrawing 관련 SwiftData Schema(V1~V5) 마이그레이션 플랜
/// V1 -> V2: DrawingVO -> BibleDrawing 모델명 및 속성 변경 (Custom)
/// V2 -> V3: BiblePageDrawing 추가(lightWeight)
/// V3 -> V4: optional 필드 2개 추가(lightWeight). **데이터 변환 없음** — 설계 §10-2
/// V4 -> V5: FavoriteVerse 엔티티 추가(lightWeight). 필사 행은 그대로
enum DrawingDataMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] {
        [DrawingSchemaV1.self, DrawingSchemaV2.self, DrawingSchemaV3.self, DrawingSchemaV4.self, DrawingSchemaV5.self, DrawingSchemaV6.self]
    }

    /// willMigrate 가 V1 행에서 뽑은 값을 didMigrate 까지 들고 있는 임시 보관. 두 단계 사이에만 값이 있다.
    private static let updatedDrawings = LockIsolated<[V1DrawingMigrationValue]>([])

    static let migrationV1toV2 = MigrationStage.custom(
        fromVersion: DrawingSchemaV1.self,
        toVersion: DrawingSchemaV2.self,
        willMigrate: { context in
            /// 기존 V1 DrawingVO에서 값만 추출한다. destination 모델은 didMigrate의 context에서 만든다.
            let drawings = try context.fetch(FetchDescriptor<DrawingSchemaV1.DrawingVO>())
            let values = drawings
                .filter { drawing in        // drawing이 비어있으면 제거
                    if drawing.lineData?.containsPKStroke == true {
                        return true
                    } else {
                        context.delete(drawing)
                        return false
                    }
                }
                .map { old in
                let id = {
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
                return V1DrawingMigrationValue(
                    id: id,
                    titleName: old.titleName,
                    titleChapter: old.titleChapter,
                    verse: old.section,
                    creationDate: old.creationDate,
                    updateDate: old.updateDate,
                    lineData: old.lineData
                )
            }
            updatedDrawings.setValue(values)
            try context.save()
        },
        didMigrate: { context in
            defer { updatedDrawings.setValue([]) }
            updatedDrawings.value
                .map { $0.makeV2Drawing() }
                .forEach { context.insert($0) }
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

    /// 즐겨찾기(`FavoriteVerse`) 엔티티만 추가한다. `BibleDrawing` · `BiblePageDrawing` 은 V4 클래스를 그대로 쓴다.
    ///
    /// - Important: forward-only 다. 이 단계를 거친 store 는 V4 빌드로 열 수 없다.
    static let migrationV4toV5 = MigrationStage.lightweight(
        fromVersion: DrawingSchemaV4.self,
        toVersion: DrawingSchemaV5.self
    )

    /// 절 필기 버전(`VerseDrawingVersion`) · 삭제 기준점(`DrawingEraseEpoch`) 엔티티를 더하고, 즐겨찾기에 optional 필드
    /// (`knownEraseEpochs`) 하나를 더한다. 필사 행은 V4 클래스를 그대로 쓴다.
    ///
    /// - Important: forward-only 다. 이 단계를 거친 store 는 V5 빌드로 열 수 없다.
    static let migrationV5toV6 = MigrationStage.lightweight(
        fromVersion: DrawingSchemaV5.self,
        toVersion: DrawingSchemaV6.self
    )

    /// 정의된 순서대로 마이그레이션 실행 (V1 -> V2, V2 -> V3, V3 -> V4, V4 -> V5, V5 -> V6)
    static var stages: [MigrationStage] {
        [
            migrationV1toV2,
            migrationV2toV3,
            migrationV3toV4,
            migrationV4toV5,
            migrationV5toV6
        ]
    }
}

/// V2 이상 저장소용 migration plan.
/// iOS 17 SwiftData는 V2 저장소를 열 때 V1 사용자 정의 단계를 포함한 전체 plan에서
/// 원본 버전을 찾지 못한다(134504). 확인된 V2 저장소부터 마지막 단계까지만 선언한다.
enum DrawingDataMigrationPlanFromV2: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] {
        [DrawingSchemaV2.self, DrawingSchemaV3.self, DrawingSchemaV4.self, DrawingSchemaV5.self, DrawingSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [
            DrawingDataMigrationPlan.migrationV2toV3,
            DrawingDataMigrationPlan.migrationV3toV4,
            DrawingDataMigrationPlan.migrationV4toV5,
            DrawingDataMigrationPlan.migrationV5toV6
        ]
    }
}
