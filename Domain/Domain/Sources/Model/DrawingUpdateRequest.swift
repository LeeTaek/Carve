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

/// N-Canvas 호환 경로에서 한 필사 행을 저장하기 위한 값 타입 요청.
///
/// SwiftData 모델을 actor 경계로 전달하지 않고, §8-7의 행 주소(`rowUUID` 또는 legacy business id)와
/// 실제로 갱신할 값만 전달한다. 신규 행의 `rowID`는 Canvas에서 모델을 만들 때 이미 선발급된 값을 사용한다.
public struct LegacyDrawingSaveRequest: Sendable {
    /// 저장 대상 장.
    public let chapter: BibleChapter
    /// 저장 대상 절.
    public let verse: Int
    /// 신규 행은 선발급 UUID, legacy 행은 기존 business id.
    public let rowID: BibleDrawingRowID
    /// `PKDrawing.dataRepresentation()`.
    public let lineData: Data?
    /// 필사 갱신 시각.
    public let updateDate: Date?
    /// N-Canvas 좌표 형식 표식. v3 행을 편집하면 2로 내려간다.
    public let drawingVersion: Int?
    /// v3 전용 레이아웃 metadata blob. N-Canvas 편집 후에는 nil이다.
    public let layoutMetadataData: Data?

    public init(
        chapter: BibleChapter,
        verse: Int,
        rowID: BibleDrawingRowID,
        lineData: Data?,
        updateDate: Date?,
        drawingVersion: Int?,
        layoutMetadataData: Data?
    ) {
        self.chapter = chapter
        self.verse = verse
        self.rowID = rowID
        self.lineData = lineData
        self.updateDate = updateDate
        self.drawingVersion = drawingVersion
        self.layoutMetadataData = layoutMetadataData
    }
}
