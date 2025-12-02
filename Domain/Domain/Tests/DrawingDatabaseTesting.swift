//
//  DrawingDatabaseTesting.swift
//  DomainTest
//
//  Created by 이택성 on 6/12/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

@testable import Domain
import CarveToolkit
import Testing
import SwiftData
import PencilKit
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
        let drawing = BibleDrawing.init(bibleTitle: .initialState, verse: 1)
        // when
        try await actor.insert(drawing)
        let storedDrawing: BibleDrawing = try #require(await actor.fetch().first)
        // then
        #expect(drawing == storedDrawing)
        
        // teardown
        try await actor.deleteAll(BibleDrawing.self)
    }
        
    @Test func migrationV1toV2() async throws {
        // given
        let title = TitleVO.init(title: .genesis, chapter: 1)
        let section = 1
        let drawing = DrawingSchemaV1.DrawingVO(bibleTitle: title,
                                                section: section,
                                                lineData: makeMockDrawingWithStroke())

        let url = URL.applicationSupportDirectory.appending(path: "MigrationTest.sqlite")
        let config = ModelConfiguration(url: url)
        var container = try ModelContainer(for: DrawingSchemaV1.DrawingVO.self,
                                           configurations: config)
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
        container = try ModelContainer(for: DrawingSchemaV2.BibleDrawing.self,
                                       migrationPlan: DrawingDataMigrationPlan.self,
                                       configurations: config)
        context = ModelContext(container)
        let predicateV2 = #Predicate<DrawingSchemaV2.BibleDrawing> {
            $0.titleName == titmeName &&
            $0.titleChapter == chapter
        }
        let descriptorV2 = FetchDescriptor(predicate: predicateV2,
                                     sortBy: [SortDescriptor(\.verse)])
        let migrationFetchedDrawing = try context.fetch(descriptorV2).first
        
        // then
        #expect(fetchedDrawing?.lineData == migrationFetchedDrawing?.lineData)

        // teardown
        try await actor.deleteAll(BibleDrawing.self)
    }
    
    
    /// 임의 drawing 추가
    func makeMockDrawingWithStroke() -> Data {
        let path = PKStrokePath(
            controlPoints: [
                .init(location: CGPoint(x: 0, y: 0),
                      timeOffset: 0,
                      size: .init(width: 5, height: 5),
                      opacity: 1,
                      force: 1,
                      azimuth: 0,
                      altitude: 0),
                .init(location: CGPoint(x: 100, y: 100),
                      timeOffset: 1,
                      size: .init(width: 5, height: 5),
                      opacity: 1,
                      force: 1,
                      azimuth: 0,
                      altitude: 0)
            ],
            creationDate: Date()
        )
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
        return PKDrawing(strokes: [stroke]).dataRepresentation()
    }
}
