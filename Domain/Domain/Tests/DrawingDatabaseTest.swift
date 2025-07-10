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
        try await self.actor.deleteAll(DrawingVO.self)
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
        try await actor.insert(drawing)
        let storedDrawings = try await drawingContext.fetch()
        
        // then
        XCTAssertEqual(drawing, storedDrawings)
    }

    func test_fetech_drawings() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let lastSection = 31
        
        // when
        try await drawingContext.setDrawing(title: title, to: lastSection)        
        let storedDrawings = try await drawingContext.fetch(title: title)
        
        // then
        XCTAssertEqual(lastSection, storedDrawings.count)
    }
}
