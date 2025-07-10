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
    
    @Model
    public class DrawingVO {
        public var bibleTitle: Data?
        public var creationDate: Date?
        public var entityName: String?
        public var id: String!
        public var isPresent: Bool?
        public var isWritten: Bool?    // 필요한 경우
        public var section: Int?
        public var titleChapter: Int?
        public var titleName: String?
        public var updateDate: Date?
        @Attribute(.externalStorage) public var lineData: Data?
        
        public init() { }
    }
}

enum DrawingSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [DrawingVO.self, BibleDrawing.self]
    }
    
    @Model
    public class DrawingVO {
        public var id: String! = ""
        public var titleName: String? = ""
        public var titleChapter: Int? = 1
        public var section: Int? = 1
        public var creationDate: Date? = Date()
        public var updateDate: Date? = Date()
        public var translation: Translation? = Translation.NKRV
        public var drawingVersion: Int? = 1
        public var isPresent: Bool? = false
        @Attribute(.externalStorage) var lineData: Data? = Data()
        
        public init(bibleTitle: TitleVO,
                    section: Int,
                    lineData: Data? = nil,
                    updateDate: Date? = Date.now
        ) {
            self.id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(section)"
            self.lineData = lineData
            self.titleName = bibleTitle.title.rawValue
            self.titleChapter = bibleTitle.chapter
            self.section = section
            self.creationDate = Date()
            self.updateDate = updateDate
        }
    }
//    
//    @Model
//    public class BibleDrawing {
//        public var id: String?
//        public var titleName: String?
//        public var titleChapter: Int?
//        public var verse: Int?
//        public var creationDate: Date?
//        public var updateDate: Date?
//        public var translation: Translation? = Translation.NKRV
//        public var drawingVersion: Int? = 1
//        public var isWritten: Bool? = false
//        @Attribute(.externalStorage) public var lineData: Data?
//        
//        public init() { }
//    }
}

enum DrawingDataMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] {
        [DrawingSchemaV1.self]
    }

    private static var updatedDrawings: [DrawingSchemaV2.DrawingVO] = []

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: DrawingSchemaV1.self,
        toVersion: DrawingSchemaV2.self,
        willMigrate: { context in
            let drawings = try context.fetch(FetchDescriptor<DrawingSchemaV1.DrawingVO>())
            updatedDrawings = drawings.map { old in
                let new = DrawingSchemaV2.DrawingVO(
                    bibleTitle: TitleVO(
                        title: BibleTitle(rawValue: old.titleName ?? "") ?? .genesis,
                        chapter: old.titleChapter ?? 1
                    ),
                    section: old.section ?? 1,
                    lineData: old.lineData,
                    updateDate: old.updateDate ?? Date()
                )
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
                new.section = old.section
                new.creationDate = old.creationDate
                new.updateDate = old.updateDate
                new.lineData = old.lineData
                return new
            }
//            try context.delete(DrawingSchemaV1.DrawingVO.self)
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
