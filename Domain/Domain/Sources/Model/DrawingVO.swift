//
//  DrawingVO.swift
//  DomainRealm
//
//  Created by 이택성 on 2/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import PencilKit
import SwiftData

@Model
public final class DrawingVO: Equatable, Sendable {
    public static func == (lhs: DrawingVO, rhs: DrawingVO) -> Bool {
        (lhs.id == rhs.id)
    }
    public var id: String!
    public var titleName: String?
    public var titleChapter: Int?
    public var section: Int?
    public var creationDate: Date?
    public var updateDate: Date?
    @Attribute(.externalStorage) public var lineData: Data?
    public var isWritten: Bool = false
    
    public init(author: String,
                lineData: PKDrawing,
                isWritten: Bool = false,
                bibleTitle: TitleVO,
                section: Int,
                updateDate: Date? = Date.now
    ) {
        self.id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(section)"
        self.lineData = lineData.dataRepresentation()
        self.isWritten = isWritten
        self.titleName = bibleTitle.title.rawValue
        self.titleChapter = bibleTitle.chapter
        self.section = section
        self.creationDate = Date()
        self.updateDate = updateDate
    }
    
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
