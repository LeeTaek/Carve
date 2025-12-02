//
//  DrawingUpdateRequest.swift
//  Domain
//
//  Created by 이택성 on 11/25/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public struct DrawingUpdateRequest: Sendable {
    public let title: TitleVO
    public let verse: Int
    public let updateLineData: Data
    public let updateDate: Date
    
    public init(
        title: TitleVO,
        verse: Int,
        updateLineData: Data,
        updateDate: Date = .now
    ) {
        self.title = title
        self.verse = verse
        self.updateLineData = updateLineData
        self.updateDate = updateDate
    }
}
