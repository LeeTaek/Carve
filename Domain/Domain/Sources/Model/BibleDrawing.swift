//
//  BibleDrawing.swift
//  DomainRealm
//
//  Created by 이택성 on 2/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import PencilKit
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
    @Attribute(.externalStorage) public var lineData: Data?
    public var isWritten: Bool = false
    
    public init(author: String,
                lineData: PKDrawing,
                isWritten: Bool = false,
                bibleTitle: BibleChapter,
                verse: Int,
                updateDate: Date? = Date.now
    ) {
        self.id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse)"
        self.lineData = lineData.dataRepresentation()
        self.isWritten = isWritten
        self.titleName = bibleTitle.title.rawValue
        self.titleChapter = bibleTitle.chapter
        self.verse = verse
        self.creationDate = Date()
        self.updateDate = updateDate
    }
    
    public init(bibleTitle: BibleChapter,
                verse: Int,
                lineData: Data? = nil,
                updateDate: Date? = Date.now
    ) {
        self.id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(verse)"
        self.lineData = lineData
        self.titleName = bibleTitle.title.rawValue
        self.titleChapter = bibleTitle.chapter
        self.verse = verse
        self.creationDate = Date()
        self.updateDate = updateDate
    }
    
    public func isUpdate() -> Bool {
        return creationDate == updateDate
    }
    
}

extension BibleDrawing {
    static var previewData: [BibleDrawing] {
        [
            BibleDrawing(bibleTitle: BibleChapter(title: .genesis, chapter: 1),
                      verse: 1,
                      updateDate: Date()),
            BibleDrawing(bibleTitle: BibleChapter(title: .genesis, chapter: 1),
                      verse: 2,
                      updateDate: Date()),
            BibleDrawing(bibleTitle: BibleChapter(title: .genesis, chapter: 1),
                      verse: 3,
                      updateDate: Date()),
            BibleDrawing(bibleTitle: BibleChapter(title: .exodus, chapter: 2),
                      verse: 1,
                      updateDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)!),
            BibleDrawing(bibleTitle: BibleChapter(title: .exodus, chapter: 2),
                      verse: 2,
                      updateDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)!),
            BibleDrawing(bibleTitle: BibleChapter(title: .revelation, chapter: 3),
                      verse: 3,
                      updateDate: Calendar.current.date(byAdding: .day, value: -2, to: .now)!)
        ]
    }
}
