//
//  DrawingSchemaV2.swift
//  Domain
//
//  Created by 이택성 on 7/15/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Domain
import Foundation
import SwiftData


public enum DrawingSchemaV2: VersionedSchema {
    public static var versionIdentifier = Schema.Version(2, 0, 0)
    
    public static var models: [any PersistentModel.Type] {
        [BibleDrawing.self]
    }
    
    @Model
    public final class BibleDrawing: Equatable, Sendable {
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
        public var drawingVersion: Int? = 1
        public var isPresent: Bool? = false
        @Attribute(.externalStorage) public var lineData: Data?
        
        public init() { }
            
        public init(bibleTitle: TitleVO,
                    verse: Int,
                    lineData: Data? = nil,
                    updateDate: Date? = Date.now
        ) {
            self.lineData = lineData
            self.titleName = bibleTitle.title.rawValue
            self.titleChapter = bibleTitle.chapter
            self.verse = verse
            self.creationDate = Date()
            self.updateDate = updateDate
            self.id = {
                if let timestamp = creationDate?.timeIntervalSince1970 {
                    return "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse).\(Int(timestamp))"
                } else {
                    return "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse).\(Date().timeIntervalSince1970)"
                }
            }()
        }
        
        public convenience init(bibleTitle: TitleVO,
                                section: Int,
                                lineData: Data? = nil,
                                updateDate: Date? = Date.now
        ) {
            self.init(bibleTitle: bibleTitle, verse: section, lineData: lineData, updateDate: updateDate)
        }
        
        public convenience init(_ bible: Domain.BibleDrawing) {
            self.init()
            self.id = bible.id
            self.titleName = bible.titleName
            self.titleChapter = bible.titleChapter
            self.verse = bible.verse
            self.creationDate = bible.creationDate
            self.updateDate = bible.updateDate
            self.translation = bible.translation
            self.drawingVersion = bible.drawingVersion
            self.isPresent = bible.isPresent
            self.lineData = bible.lineData
        }
        
        func toDomain() -> Domain.BibleDrawing {
            let domain = Domain.BibleDrawing(
                id: self.id,
                titleName: self.titleName,
                titleChapter: self.titleChapter,
                verse: self.verse,
                lineData: self.lineData,
                updateDate: self.updateDate,
                translation: self.translation,
                drawingVersion: self.drawingVersion,
                isPresent: self.isPresent,
                creationDate: self.creationDate
            )
            return domain
        }
    }
}

// Data 모듈 안에서만 사용
typealias BibleDrawing = DrawingSchemaV2.BibleDrawing
