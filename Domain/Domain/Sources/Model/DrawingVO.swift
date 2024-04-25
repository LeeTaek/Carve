//
//  DrawingVO.swift
//  DomainRealm
//
//  Created by 이택성 on 2/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import PencilKit

public class DrawingVO: Equatable {
    public static func == (lhs: DrawingVO, rhs: DrawingVO) -> Bool {
        (lhs.id == rhs.id)
    }
    
    public var keyType: SwiftDataStorageKeyType
    public var id: String
    public var lineData: Data
    public var isWritten: Bool = false
    public var bibleTitle: TitleVO?
    public var section: Int
    
    public init(author: String,
                lineData: PKDrawing,
                isWritten: Bool = false,
                bibleTitle: TitleVO,
                section: Int) {
        self.keyType = .drawing
        self.id = "\(bibleTitle.title.koreanTitle()).\(bibleTitle.chapter).\(section)"
        self.lineData = lineData.dataRepresentation()
        self.isWritten = isWritten
        self.bibleTitle = bibleTitle
        self.section = section
    }
    
    public init(bibleTitle: TitleVO,
                section: Int,
                lineData: PKDrawing = .init()
    ) {
        self.keyType = .drawing
        self.id = "\(bibleTitle.title.rawValue).\(bibleTitle.chapter).\(section))"
        self.lineData = lineData.dataRepresentation()
        self.bibleTitle = bibleTitle
        self.section = section
    }
    
}
