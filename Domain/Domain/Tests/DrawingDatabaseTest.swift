//
//  DrawingDatabaseTest.swift
//  DomainTest
//
//  Created by 이택성 on 5/16/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import XCTest
@testable import Domain
import SwiftData

import Dependencies

final class DrawingDatabaseTest: XCTestCase {
    @Dependency(\.createSwiftDataActor) var actor
    @Dependency(\.drawingData) var drawingContext

    override func tearDown() async throws {
        try await self.actor.deleteAll(BibleDrawing.self)
    }
    
    func test_actor_insert() async throws {
        // given
        // iOS 17 SwiftData 는 모델 초기화 전에 해당 스키마의 컨테이너가 만들어져 있어야 한다.
        let actor = self.actor
        let drawing = BibleDrawing.init(bibleTitle: .initialState, verse: 1)
        // 모델은 actor 로 넘긴 뒤 다시 만지지 않는다 — 넣은 행은 행 식별자(rowUUID)로 알아본다.
        let expectedRowUUID = drawing.rowUUID
        
        // when
        try await actor.insert(drawing)
        let storedDrawing: BibleDrawing? = try ModelContext(actor.modelContainer).fetch(FetchDescriptor<BibleDrawing>()).first
        
        // then
        XCTAssertNotNil(storedDrawing)
        XCTAssertEqual(storedDrawing?.rowUUID, expectedRowUUID)
    }
    
    func test_fetch_drawing() async throws {
        // given
        let title = BibleChapter.init(title: .genesis, chapter: 1)
        let lastVerse = 1
        let drawing = BibleDrawing(bibleTitle: title, verse: lastVerse)
        let expectedRowUUID = drawing.rowUUID
        
        // when
        try await actor.insert(drawing)
        let storedDrawings = try await drawingContext.fetchForLegacyCanvas(chapter: title).value.first
        
        // then
        XCTAssertNotNil(storedDrawings)
        XCTAssertEqual(storedDrawings?.rowUUID, expectedRowUUID)
    }

}
