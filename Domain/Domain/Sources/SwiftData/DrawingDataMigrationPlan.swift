//
//  DrawingDataMigrationPlan.swift
//  Domain
//
//  Created by 이택성 on 7/10/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import SwiftData

public enum DrawingSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    
    public static var models: [any PersistentModel.Type] {
        [DrawingVO.self]
    }    
}

enum DrawingSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [BibleDrawing.self]
    }

    @Model
    public class BibleDrawing {
        public var id: String!
        public var titleName: String?
        public var titleChapter: Int?
        public var verse: Int?
        public var creationDate: Date?
        public var updateDate: Date?
        public var translation: Translation? = Translation.NKRV
        public var drawingVersion: Int? = 1
        public var isPresent: Bool? = false
        @Attribute(.externalStorage) public var lineData: Data?
        
        public init() { }
    }
}

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
            let drawings = try context.fetch(FetchDescriptor<DrawingVO>())
            updatedDrawings = drawings.map { old in
                let new = DrawingSchemaV2.BibleDrawing()
                new.id = {
                    if let title = old.titleName,
                       let chapter = old.titleChapter,
                       let section = old.section,
                       let createdAt = old.creationDate {
                        let timestamp = createdAt.timeIntervalSince1970
                        return "\(title).\(chapter).\(section).\(timestamp)"
                    } else {
                        return old.id
                    }
                }()
                new.titleName = old.titleName
                new.titleChapter = old.titleChapter
                new.verse = old.section
                new.creationDate = old.creationDate
                new.updateDate = old.updateDate
                new.lineData = old.lineData
                return new
            }
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
