//
//  DrawingDatabase.swift
//  Domain
//
//  Created by 이택성 on 5/10/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI
import SwiftData

import Dependencies

public struct DrawingDatabase: Sendable, Database {
    public typealias Item = DrawingVO
    @Dependency(\.createSwiftDataActor) public var actor
    
    /// 테스트를 위한 fetch
    public func fetch() async throws -> DrawingVO {
        if let storedDrawing: DrawingVO = try await actor.fetch().first {
            return storedDrawing
        } else {
            try await actor.insert(DrawingVO.init(bibleTitle: .initialState, section: 1))
            return DrawingVO.init(bibleTitle: .initialState, section: 1)
        }
    }
    
    /// 한 장의 필사 데이터를 모두 불러옴
    /// - Parameter title: 가져올 성경의 이름과 장
    /// - Returns: 해당 장의 필사 데이터
    public func fetch(title: TitleVO) async throws -> [DrawingVO] {
        let titleName = title.title.rawValue
        let chapter = title.chapter
        let predicate = #Predicate<DrawingVO> {
            $0.titleName == titleName &&
            $0.titleChapter == chapter
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.section)])
        let storedDrawing: [DrawingVO] = try await actor.fetch(descriptor)
        return storedDrawing
    }
    
    /// 해당 아이디의 필사 데이터를 모두 불러옴
    public func fetch(title: TitleVO, section: Int) async throws -> DrawingVO? {
        let titleName = title.title.rawValue
        let chapter = title.chapter
        let predicate = #Predicate<DrawingVO> {
            $0.titleName == titleName
            && $0.titleChapter == chapter
            && $0.section == section
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.section)])
        let storedDrawing: DrawingVO? = try await actor.fetch(descriptor).first
        return storedDrawing
    }
    
    /// 해당 절의 필사 데이터 모두 가져오기
    /// - Parameters:
    ///   - title: 해상 성경의 이름과 장
    ///   - section: 절
    /// - Returns: 해당 절의 필사 데이터를 전부 반환
    public func fetchDrawings(title: TitleVO, section: Int) async throws -> [DrawingVO]? {
        let titleName = title.title.rawValue
        let chapter = title.chapter
        let predicate = #Predicate<DrawingVO> {
            $0.titleName == titleName
            && $0.titleChapter == chapter
            && $0.section == section
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.updateDate, order: .reverse)])
        let storedDrawing: [DrawingVO]? = try await actor.fetch(descriptor)
        return storedDrawing
    }
    
    
    public func add(item: DrawingVO) async throws {
        try await actor.insert(item)
    }
    
    public func update(item: DrawingVO) async throws {
        try await actor.update(item.id) { (oldValue: DrawingVO) async in
            oldValue.lineData = item.lineData
            oldValue.updateDate = item.updateDate
        }
    }
    
    public func setDrawing(title: TitleVO, to last: Int) async throws {
        let drawings: [DrawingVO] = try await fetch(title: title)
        for drawing in drawings {
            guard let section = drawing.section else { continue }
            if section <= last {
                let newDrawing = DrawingVO(bibleTitle: title, section: section)
                if drawing.lineData != nil {
                    newDrawing.lineData = drawing.lineData
                }
                try await actor.insert(newDrawing)
            } else {
                try await actor.delete(drawing)
            }
        }
        for section in 1...last {
            let drawing = DrawingVO(bibleTitle: title, section: section)
            try await actor.insert(drawing)
        }
        
    }
    
    public func updateDrawing(drawing: DrawingVO) async throws {
        let title = TitleVO(title: BibleTitle(rawValue: drawing.titleName!)!, chapter: drawing.titleChapter!)
        do {
            if (try await fetch(title: title, section: drawing.section!)) != nil {
                try await update(item: drawing)
            } else {
                try await actor.insert(drawing)
            }
            Log.debug("update drawing", drawing.id ?? "")
        } catch {
            Log.error("failed to update drawing", error)
        }
        Log.debug("update drawing", drawing)
    }
    
    public func updateDrawings(drawings: [DrawingVO]) async throws {
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
