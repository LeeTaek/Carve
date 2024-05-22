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
        self.actor = try await createActor()
        self.drawingDatabase = drawingContext
    }

    override func tearDown() async throws {
        self.actor.modelContainer.deleteAllData()
//        try await self.actor.modelContext.delete(model: DrawingVO.self)
        self.actor = nil
        self.drawingDatabase = nil
    }
    
    func test_actor_insert() async throws {
        // given
        let drawing = DrawingVO.init(bibleTitle: .initialState, section: 1)
        
        // when
        try await actor.insert(drawing)
        let storedDrawing: DrawingVO? = try await actor.fetch().first
        
        // then
        XCTAssertEqual(drawing, storedDrawing)
    }
    
    func test_fetch_drawing() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let lastSection = 1
        let drawing = DrawingVO(bibleTitle: title, section: lastSection)
        
        // when
        try await drawingDatabase.setDrawing(title: title, to: lastSection)
        let storedDrawings = try await drawingDatabase.fetch()
        
        // then
        XCTAssertEqual(drawing, storedDrawings)
    }

    func test_fetech_drawings() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let lastSection = 31
        
        // when
        try await drawingDatabase.setDrawing(title: title, to: lastSection)        
        let storedDrawings = try await drawingDatabase.fetch(title: title)
        
        // then
        XCTAssertEqual(lastSection, storedDrawings.count)
    }
}
