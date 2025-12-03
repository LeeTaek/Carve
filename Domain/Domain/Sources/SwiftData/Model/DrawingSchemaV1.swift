//
//  DrawingSchemaV1.swift
//  Domain
//
//  Created by 이택성 on 2/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import SwiftData

public enum DrawingSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    
    public static var models: [any PersistentModel.Type] {
        [DrawingVO.self]
    }
    
    @Model
    public final class DrawingVO: Equatable {
        public static func == (lhs: DrawingVO, rhs: DrawingVO) -> Bool {
            (lhs.id == rhs.id)
        }
        public var id: String!
        public var titleName: String?
        public var titleChapter: Int?
        public var section: Int?
        public var creationDate: Date?
        public var updateDate: Date?
        public var isPresent: Bool? = false
        @Attribute(.externalStorage) public var lineData: Data?
        public var verse: Int?

        public init() { }
            
        public init(bibleTitle: BibleChapter,
                    verse: Int,
                    lineData: Data? = nil,
                    updateDate: Date? = Date.now
        ) {
            self.id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse)"
            self.lineData = lineData
            self.titleName = bibleTitle.title.rawValue
            self.titleChapter = bibleTitle.chapter
            self.section = verse
            self.creationDate = Date()
            self.updateDate = updateDate
            self.verse = verse
        }
        
        public convenience init(bibleTitle: BibleChapter,
                                section: Int,
                                lineData: Data? = nil,
                                updateDate: Date? = Date.now
        ) {
            self.init(bibleTitle: bibleTitle, verse: section, lineData: lineData, updateDate: updateDate)
        }
    }

}

public typealias DrawingVO = DrawingSchemaV1.DrawingVO
