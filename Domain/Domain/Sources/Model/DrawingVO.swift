//
//  DrawingVO.swift
//  DomainRealm
//
//  Created by 이택성 on 2/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
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
    public var isPresent: Bool? = false
    @Attribute(.externalStorage) public var lineData: Data?
    
    public init() { }
        
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
