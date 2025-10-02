//
//  DrawingDatabase.swift
//  Domain
//
//  Created by 이택성 on 5/10/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import SwiftUI
import SwiftData

import Dependencies

public struct DrawingDatabase: DrawingRepository {
    @Dependency(\.createSwiftDataActor) public var actor
    
    /// 한 장의 필사 데이터를 모두 불러옴
    /// - Parameter title: 가져올 성경의 이름과 장
    /// - Returns: 해당 장의 필사 데이터
    public func fetch(title: TitleVO) async throws -> [Domain.BibleDrawing] {
        let titleName = title.title.rawValue
        let chapter = title.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName &&
            $0.titleChapter == chapter
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.verse)])
        let storedDrawing: [BibleDrawing] = try await actor.fetch(descriptor)
        return storedDrawing.map { $0.toDomain() }
    }
    
    /// 해당 아이디의 필사 데이터 불러옴
    public func fetch(drawing: Domain.BibleDrawing) async throws -> Domain.BibleDrawing? {
        let id = drawing.id
        let predicate = #Predicate<BibleDrawing> {
            $0.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.verse)])
        let storedDrawing: BibleDrawing? = try await actor.fetch(descriptor).first
        return storedDrawing?.toDomain()
    }
    
    /// 해당 절의 필사 데이터 모두 가져오기
    /// - Parameters:
    ///   - title: 해상 성경의 이름과 장
    ///   - section: 절
    /// - Returns: 해당 절의 필사 데이터를 전부 반환
    public func fetchDrawings(title: TitleVO, verse: Int) async throws -> [Domain.BibleDrawing] {
        let titleName = title.title.rawValue
        let chapter = title.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName
            && $0.titleChapter == chapter
            && $0.verse == verse
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.updateDate, order: .reverse)])
        let storedDrawing: [BibleDrawing] = try await actor.fetch(descriptor)
        Log.debug("Drew Log Count:", storedDrawing.count)
        
        return storedDrawing.map { $0.toDomain() }
    }
    
    public func update(item: Domain.BibleDrawing) async throws {
        let item = BibleDrawing(item)
        try await actor.update(item.id) { (oldValue: BibleDrawing) async in
            oldValue.lineData = item.lineData
            oldValue.updateDate = item.updateDate
        }
    }
    
    public func updateDrawing(drawing: Domain.BibleDrawing) async throws {
        let drawing = BibleDrawing(drawing)
        do {
            if (try await fetch(drawing: drawing.toDomain())) != nil {
                try await update(item: drawing.toDomain())
            } else {
                try await actor.insert(drawing)
            }
            Log.debug("update drawing", drawing.id ?? "")
        } catch {
            Log.error("failed to update drawing", error)
        }
    }
    
    public func updateDrawings(drawings: [Domain.BibleDrawing]) async throws {
        for drawing in drawings {
            try await updateDrawing(drawing: drawing)
        }
    }
    
    public func deleteAll() async throws {
        try await actor.deleteAll(BibleDrawing.self)
    }
    
    public func databaseIsEmpty() async throws -> Bool {
        try await actor.databaseIsEmpty(BibleDrawing.self)
    }
    
}

extension DrawingDatabase: DependencyKey {
    public static let liveValue: DrawingDatabase = Self()
    public static var testValue: DrawingDatabase = {
        let database = withDependencies {
            $0.createSwiftDataActor = .testValue
        } operation: {
            DrawingDatabase()
        }
        return database
    }()
    public static var previewValue: DrawingDatabase = {
        let database = withDependencies {
            $0.createSwiftDataActor = .previewValue
        } operation: {
            DrawingDatabase()
        }
        return database
    }()
}

extension DependencyValues {
    public var drawingData: DrawingDatabase {
        get { self[DrawingDatabase.self] }
        set { self[DrawingDatabase.self] = newValue }
    }
}
