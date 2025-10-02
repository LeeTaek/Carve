//
//  BibleDrawing.swift
//  Domain
//
//  Created by 이택성 on 10/2/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public struct BibleDrawing: Equatable, Identifiable, Sendable {
    public static func == (lhs: BibleDrawing, rhs: BibleDrawing) -> Bool {
        (lhs.id == rhs.id)
    }
    public var id: String
    public var titleName: String?
    public var titleChapter: Int?
    public var verse: Int?
    public var creationDate: Date?
    public var updateDate: Date?
    public var translation: Translation? = Translation.NKRV
    public var drawingVersion: Int? = 1
    public var isPresent: Bool? = false
    public var lineData: Data?
        
    public init(
        id: String,
        titleName: String?,
        titleChapter: Int?,
        verse: Int?,
        lineData: Data?,
        updateDate: Date?,
        translation: Translation?,
        drawingVersion: Int?,
        isPresent: Bool?,
        creationDate: Date?
    ) {
        self.id = id
        self.titleName = titleName
        self.titleChapter = titleChapter
        self.verse = verse
        self.creationDate = creationDate
        self.updateDate = updateDate
        self.translation = translation
        self.drawingVersion = drawingVersion
        self.isPresent = isPresent
        self.lineData = lineData
    }
    
    
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
        self.id = ""
        self.id = {
            if let timestamp = creationDate?.timeIntervalSince1970 {
                return "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse).\(Int(timestamp))"
            } else {
                return "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse).\(Date().timeIntervalSince1970)"
            }
        }()
    }
    
    public init(bibleTitle: TitleVO,
                section: Int,
                lineData: Data? = nil,
                updateDate: Date? = Date.now
    ) {
        self.init(bibleTitle: bibleTitle, verse: section, lineData: lineData, updateDate: updateDate)
    }
}
