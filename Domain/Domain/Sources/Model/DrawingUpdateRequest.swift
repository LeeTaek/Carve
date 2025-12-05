//
//  DrawingUpdateRequest.swift
//  Domain
//
//  Created by 이택성 on 11/25/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

/// BibleDrawing의 drawing 데이터 변경을 전달하기 위한 업데이트 요청 모델.
public struct DrawingUpdateRequest: Sendable {
    /// 성경(제목/장).
    public let chapter: BibleChapter
    /// 변경 대상이 되는 절(verse).
    public let verse: Int
    /// 업데이트할 PKDrawing Data.
    public let updateLineData: Data
    /// 이 업데이트 요청이 생성된 시각.
    public let updateDate: Date
    
    public init(
        chapter: BibleChapter,
        verse: Int,
        updateLineData: Data,
        updateDate: Date = .now
    ) {
        self.chapter = chapter
        self.verse = verse
        self.updateLineData = updateLineData
        self.updateDate = updateDate
    }
}
