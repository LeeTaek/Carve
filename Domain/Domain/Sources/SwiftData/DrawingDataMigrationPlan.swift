//
//  DrawingDataMigrationPlan.swift
//  Domain
//
//  Created by 이택성 on 7/10/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import SwiftData


enum MigrationPlanV1Only: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] {
        [DrawingSchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }
}

enum DrawingDataMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] {
        [DrawingSchemaV1.self, DrawingSchemaV2.self]
    }

    private static var updatedDrawings: [DrawingSchemaV2.BibleDrawing] = []

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: DrawingSchemaV1.self,
        toVersion: DrawingSchemaV2.self,
        willMigrate: { context in
            let drawings = try context.fetch(FetchDescriptor<DrawingSchemaV1.DrawingVO>())
            updatedDrawings = drawings.map { old in
                let new = DrawingSchemaV2.BibleDrawing()
                new.id = {
                    if let title = old.titleName,
                       let chapter = old.titleChapter,
                       let section = old.section,
                       let createdAt = old.creationDate {
                        let timestamp = Int(createdAt.timeIntervalSince1970)
                        return "\(title).\(chapter).\(section).\(timestamp)"
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

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
}
