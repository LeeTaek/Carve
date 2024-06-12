//
//  DrawingDatabaseTesting.swift
//  DomainTest
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

@testable import Domain
import Testing
import SwiftData

import Dependencies

final class DrawingDatabaseTesting {
    var actor: SwiftDatabaseActor!
    var drawingDatabase: DrawingDatabase!
    
    init() async throws {
        @Dependency(\.createSwiftDataActor) var createActor
        @Dependency(\.drawingData) var drawingContext
        self.actor = try await createActor()
        self.drawingDatabase = drawingContext
    }
    
    deinit {
        actor.modelContainer.deleteAllData()
        actor = nil
        drawingDatabase = nil
    }
    
    @Test func actorInsert() async throws {
        // given
        let drawing = DrawingVO.init(bibleTitle: .initialState, section: 1)
        // when
        try await actor.insert(drawing)
        let storedDrawing: DrawingVO = try #require(await actor.fetch().first)
        // then
        #expect(drawing == storedDrawing)
    }
    
    @Test func fetchDrawing() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let lastSection = 1
        let drawing = DrawingVO(bibleTitle: title, section: lastSection)
        // when
        try await drawingDatabase.setDrawing(title: title, to: lastSection)
        let storedDrawings = try #require(await drawingDatabase.fetch())
        // then
        #expect(drawing == storedDrawings)
    }
    
    @Test func fetchDrawings() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let lastSection = 31
        // when
        try await drawingDatabase.setDrawing(title: title, to: lastSection)
        let storedDrawings = try #require(await drawingDatabase.fetch(title: title))
        // then
        #expect(lastSection == storedDrawings.count)
    }
}
