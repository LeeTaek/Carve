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
    public let id: String!
    @Relationship public let bibleTitle: TitleVO!
    public let section: Int!
    public var lineData: Data?
    public var isWritten: Bool = false
    
    public init(author: String,
                lineData: PKDrawing,
                isWritten: Bool = false,
                bibleTitle: TitleVO,
                section: Int) {
        self.id = "\(bibleTitle.title.koreanTitle()).\(bibleTitle.chapter).\(section)"
        self.lineData = lineData.dataRepresentation()
        self.isWritten = isWritten
        self.bibleTitle = bibleTitle
        self.section = section
    }
    
    public init(bibleTitle: TitleVO,
                section: Int,
                lineData: Data? = nil
    ) {
        self.id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(section)"
        self.lineData = lineData
        self.bibleTitle = bibleTitle
        self.section = section
    }
    
}
