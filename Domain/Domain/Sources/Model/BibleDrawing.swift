//
//  BibleDrawing.swift
//  Domain
//
//  Created by 이택성 on 7/10/25.
//  Copyright © 2025 leetaek. All rights reserved.
//


import Foundation
import SwiftData

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
    public var isWritten: Bool? = false
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
        self.id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse).\(creationDate?.description ?? "")"
        self.updateDate = updateDate
    }
    
}
