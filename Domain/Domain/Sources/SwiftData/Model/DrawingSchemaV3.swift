//
//  DrawingSchemaV3.swift
//  Domain
//
//  Created by 이택성 on 12/2/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import SwiftData

public enum DrawingSchemaV3: VersionedSchema {
    public static var versionIdentifier = Schema.Version(3, 0, 0)
    
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
    }
    
    /// 장에 해당하는 화면 전체 필사 데이터용 모델
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
            bibleTitle: TitleVO,
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

public typealias BibleDrawing = DrawingSchemaV3.BibleDrawing
public typealias BiblePageDrawing = DrawingSchemaV3.BiblePageDrawing

extension Array where Element == BibleDrawing {
    /// 여러 BibleDrawing 중 메인 Drawing 하나를 선택
     /// 1. isPresent == true 가 있으면 그걸 우선
     /// 2. 없으면 updateDate 기준으로 최신 것을 선택
     public func mainDrawing() -> BibleDrawing? {
         // 1) isPresent == true 데이터 우선
         if let active = self.first(where: { $0.isPresent == true }) {
             return active
         }
         
         // 2) updateDate 기준 최신 데이터
         return self.max {
             ($0.updateDate ?? .distantPast) < ($1.updateDate ?? .distantPast)
         }
     }
}
