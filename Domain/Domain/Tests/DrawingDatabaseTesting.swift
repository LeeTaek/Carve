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

final class DrawingDatabaseTesting {
    init() async throws {
    }
    
    deinit {
    }
    
    @Test func actorInsert() async throws {
        // given
        // 테스트 간 공유되는 dependency 컨테이너 대신 이 테스트 전용 컨테이너를 쓴다.
        let container = try ModelContainer(
            for: AppStoreSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let actor = SwiftDatabaseActor(modelContainer: container)
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
        let directory = try V4StoreHarness.makeStoreDirectory()
        defer { V4StoreHarness.removeStoreDirectory(directory) }
        let title = BibleChapter.init(title: .genesis, chapter: 1)
        let section = 1
        let url = V4StoreHarness.storeURL(in: directory)
        let config = ModelConfiguration(url: url)
        let titmeName = title.title.rawValue
        let chapter = title.chapter

        let originalData: Data? = try {
            let container = try ModelContainer(
                for: Schema(versionedSchema: DrawingSchemaV1.self),
                configurations: config
            )
            let context = ModelContext(container)
            context.insert(DrawingSchemaV1.DrawingVO(
                bibleTitle: title,
                section: section,
                lineData: makeMockDrawingWithStroke()
            ))
            try context.save()

            let predicate = #Predicate<DrawingSchemaV1.DrawingVO> {
                $0.titleName == titmeName && $0.titleChapter == chapter
            }
            let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.section)])
            return try context.fetch(descriptor).first?.lineData
        }()

        let migratedData: Data? = try {
            let container = try ModelContainer(
                for: AppStoreSchema.schema,
                migrationPlan: DrawingDataMigrationPlan.self,
                configurations: config
            )
            let context = ModelContext(container)
            let predicate = #Predicate<BibleDrawing> {
                $0.titleName == titmeName && $0.titleChapter == chapter
            }
            let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.verse)])
            return try context.fetch(descriptor).first?.lineData
        }()

        #expect(originalData == migratedData)
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
