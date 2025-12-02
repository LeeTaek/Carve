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
        let drawing = BibleDrawing.init(bibleTitle: .initialState, verse: 1)
        
        // when
        try await actor.insert(drawing)
        let storedDrawing: BibleDrawing? = try await actor.fetch().first
        
        // then
        XCTAssertEqual(drawing, storedDrawing)
    }
    
    func test_fetch_drawing() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let lastVerse = 1
        let drawing = BibleDrawing(bibleTitle: title, verse: lastVerse)
        
        // when
        try await actor.insert(drawing)
        let storedDrawings = try await drawingContext.fetch(title: title).first
        
        // then
        XCTAssertEqual(drawing, storedDrawings)
    }

}
