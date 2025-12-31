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


/// BibleDrawing 관련 SwiftData Schema(V1~V3) 마이그레이션 플랜
/// V1 -> V2: DrawingVO -> BibleDrawing 모델명 및 속성 변경 (Custom)
/// V2 -> V3: BiblePageDrawing 추가(lightWeight)
enum DrawingDataMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] {
        [
            DrawingSchemaV1.self,
            DrawingSchemaV2.self,
            DrawingSchemaV3.self,
            DrawingSchemaV3Minor1.self
        ]
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
    
    static let migrationV3toMinor1 = MigrationStage.lightweight(
        fromVersion: DrawingSchemaV3.self,
        toVersion: DrawingSchemaV3Minor1.self
    )

    /// 정의된 순서대로 마이그레이션 실행 (V1 -> V2, V2 -> V3)
    static var stages: [MigrationStage] {
        [
            migrationV1toV2,
            migrationV2toV3,
            migrationV3toMinor1
        ]
    }
}
