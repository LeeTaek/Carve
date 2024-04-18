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
        (lhs.bibleTitle == rhs.bibleTitle) &&
        (lhs.section == rhs.section) &&
        (lhs.lineData == rhs.lineData)
    }

    var author: String
    var name: String
    public var lineData: PKDrawing
    var isWritten: Bool = false
    public var bibleTitle: TitleVO
    public var section: Int

    public init(author: String,
                name: String,
                lineData: PKDrawing,
                isWritten: Bool,
                bibleTitle: TitleVO,
                section: Int) {
        self.author = author
        self.name = name
        self.lineData = lineData
        self.isWritten = isWritten
        self.bibleTitle = bibleTitle
        self.section = section
    }

    public init(bibleTitle: TitleVO,
                section: Int,
                lineData: PKDrawing = .init()
    ) {
        self.author = "leetaek"
        self.name = "leetaek"
        self.bibleTitle = bibleTitle
        self.section = section
        self.lineData = lineData
    }

}
