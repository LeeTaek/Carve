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
    var actor: SwiftDatabaseActor!
    var drawingDatabase: DrawingDatabase!

    override func setUp() async throws {
        @Dependency(\.createSwiftDataActor) var createActor
        @Dependency(\.drawingData) var drawingContext
        self.actor = createActor
        self.drawingDatabase = drawingContext
    }

    override func tearDown() async throws {
        self.actor.modelContainer.deleteAllData()
//        try await self.actor.modelContext.delete(model: BibleDrawing.self)
        self.actor = nil
        self.drawingDatabase = nil
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
        let title = BibleChapter.init(title: .genesis, chapter: 1)
        let lastVerse = 1
        let drawing = BibleDrawing(bibleTitle: title, verse: lastVerse)
        
        // when
        try await drawingDatabase.setDrawing(title: title, to: lastVerse)
        let storedDrawings = try await drawingDatabase.fetch()
        
        // then
        XCTAssertEqual(drawing, storedDrawings)
    }

    func test_fetech_drawings() async throws {
        // given
        let title = BibleChapter.init(title: .genesis, chapter: 1)
        let lastVerse = 31
        
        // when
        try await drawingDatabase.setDrawing(title: title, to: lastVerse)
        let storedDrawings = try await drawingDatabase.fetch(title: title)
        
        // then
        XCTAssertEqual(lastVerse, storedDrawings.count)
    }
}
