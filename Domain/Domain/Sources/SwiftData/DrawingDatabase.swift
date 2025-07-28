//
//  DrawingDatabase.swift
//  Domain
//
//  Created by 이택성 on 5/10/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import SwiftUI
import SwiftData

import Dependencies

public struct DrawingDatabase: Sendable, Database {
    public typealias Item = BibleDrawing
    @Dependency(\.createSwiftDataActor) public var actor
    
    /// 테스트를 위한 fetch
    public func fetch() async throws -> BibleDrawing {
        if let storedDrawing: BibleDrawing = try await actor.fetch().first {
            return storedDrawing
        } else {
            try await actor.insert(BibleDrawing.init(bibleTitle: .initialState, verse: 1))
            return BibleDrawing.init(bibleTitle: .initialState, verse: 1)
        }
    }
    
    /// 한 장의 필사 데이터를 모두 불러옴
    /// - Parameter title: 가져올 성경의 이름과 장
    /// - Returns: 해당 장의 필사 데이터
    public func fetch(title: TitleVO) async throws -> [BibleDrawing] {
        let titleName = title.title.rawValue
        let chapter = title.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName &&
            $0.titleChapter == chapter
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.verse)])
        let storedDrawing: [BibleDrawing] = try await actor.fetch(descriptor)
        return storedDrawing
    }
    
    /// 해당 아이디의 필사 데이터 불러옴
    public func fetch(drawing: BibleDrawing) async throws -> BibleDrawing? {
        let id = drawing.id
        let predicate = #Predicate<BibleDrawing> {
            $0.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.verse)])
        let storedDrawing: BibleDrawing? = try await actor.fetch(descriptor).first
        return storedDrawing
    }
    
    /// 해당 절의 필사 데이터 모두 가져오기
    /// - Parameters:
    ///   - title: 해상 성경의 이름과 장
    ///   - section: 절
    /// - Returns: 해당 절의 필사 데이터를 전부 반환
    public func fetchDrawings(title: TitleVO, verse: Int) async throws -> [BibleDrawing]? {
        let titleName = title.title.rawValue
        let chapter = title.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName
            && $0.titleChapter == chapter
            && $0.verse == verse
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.updateDate, order: .reverse)])
        let storedDrawing: [BibleDrawing]? = try await actor.fetch(descriptor)
        Log.debug("Drew Log Count:", storedDrawing?.count)
        return storedDrawing
    }
    
    
    public func add(item: BibleDrawing) async throws {
        try await actor.insert(item)
    }
    
    public func update(item: BibleDrawing) async throws {
        try await actor.update(item.id) { (oldValue: BibleDrawing) async in
            oldValue.lineData = item.lineData
            oldValue.updateDate = item.updateDate
        }
    }
    
    public func setDrawing(title: TitleVO, to last: Int) async throws {
        let drawings: [BibleDrawing] = try await fetch(title: title)
        for drawing in drawings {
            guard let verse = drawing.verse else { continue }
            if verse <= last {
                let newDrawing = BibleDrawing(bibleTitle: title, verse: verse)
                if drawing.lineData != nil {
                    newDrawing.lineData = drawing.lineData
                }
                try await actor.insert(newDrawing)
            } else {
                try await actor.delete(drawing)
            }
        }
        for verse in 1...last {
            let drawing = BibleDrawing(bibleTitle: title, verse: verse)
            try await actor.insert(drawing)
        }
        
    }
    
    public func updateDrawing(drawing: BibleDrawing) async throws {
        do {
            if (try await fetch(drawing: drawing)) != nil {
                try await update(item: drawing)
            } else {
                try await actor.insert(drawing)
            }
            Log.debug("update drawing", drawing.id ?? "")
        } catch {
            Log.error("failed to update drawing", error)
        }
    }
    
    public func updateDrawings(drawings: [BibleDrawing]) async throws {
        for drawing in drawings {
            try await updateDrawing(drawing: drawing)
        }
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
