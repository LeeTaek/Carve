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
import Foundation

import Dependencies

final class DrawingDatabaseTesting {
    @Dependency(\.createSwiftDataActor) var actor
    @Dependency(\.drawingData) var drawingContext

    
    init() async throws {
    }
    
    deinit {
    }
    
    @Test func actorInsert() async throws {
        // given
        let drawing = DrawingVO.init(bibleTitle: .initialState, section: 1)
        // when
        try await actor.insert(drawing)
        let storedDrawing: DrawingVO = try #require(await actor.fetch().first)
        // then
        #expect(drawing == storedDrawing)
        
        // teardown
        try await actor.deleteAll(DrawingVO.self)
    }
    
    @Test func fetchDrawing() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let lastSection = 1
        let drawing = DrawingVO(bibleTitle: title, section: lastSection)
        // when
        try await drawingContext.setDrawing(title: title, to: lastSection)
        let storedDrawings = try #require(await drawingContext.fetch())
        // then
        #expect(drawing == storedDrawings)
        
        // teardown
        try await actor.deleteAll(DrawingVO.self)
    }
    
    @Test func fetchDrawings() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let lastSection = 31
        // when
        try await drawingContext.setDrawing(title: title, to: lastSection)
        let storedDrawings = try #require(await drawingContext.fetch(title: title))
        // then
        #expect(lastSection == storedDrawings.count)
        
        // teardown
        try await actor.deleteAll(DrawingVO.self)
    }
    
    
    @Test func migrationV1toV2() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let section = 1
        let drawing = DrawingSchemaV1.DrawingVO(bibleTitle: title, section: section)

        let url = URL.applicationSupportDirectory.appending(path: "MigrationTest.sqlite")
        let config = ModelConfiguration(url: url)
        var container = try ModelContainer(for: DrawingSchemaV1.DrawingVO.self, configurations: config)
        var context = ModelContext(container)
        context.insert(drawing)
        try context.save()
        
        let titmeName = title.title.rawValue
        let chapter = title.chapter
        
        let predicate = #Predicate<DrawingSchemaV1.DrawingVO> {
            $0.titleName == titmeName &&
            $0.titleChapter == chapter
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.section)])
        let fetchedDrawing = try context.fetch(descriptor).first
        
        
        // when
        container = try ModelContainer(for: DrawingSchemaV2.DrawingVO.self,
                                       migrationPlan: DrawingDataMigrationPlan.self,
                                       configurations: config)
        context = ModelContext(container)
        let predicateV2 = #Predicate<DrawingSchemaV2.DrawingVO> {
            $0.titleName == titmeName &&
            $0.titleChapter == chapter
        }
        let descriptorV2 = FetchDescriptor(predicate: predicateV2,
                                     sortBy: [SortDescriptor(\.section)])
        let migrationFetchedDrawing = try context.fetch(descriptorV2).first
        
        // then
        let timestamp = Int(fetchedDrawing?.creationDate?.timeIntervalSince1970 ?? 0)
        let originId = "\(drawing.titleName ?? "").\(drawing.titleChapter?.description ?? "").\(section)"
        #expect("\(originId).\(timestamp)" == migrationFetchedDrawing?.id)
    }
}
