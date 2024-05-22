//
//  DrawingDatabase.swift
//  Domain
//
//  Created by 이택성 on 5/10/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI
@preconcurrency import SwiftData

import Dependencies

public struct DrawingDatabase: Sendable, Database {
    public typealias Item = DrawingVO
    
    public func fetch() async throws -> DrawingVO {
        @Dependency(\.createSwiftDataActor) var createActor
        let actor = try await createActor()
        if let storedDrawing: DrawingVO = try await actor.fetch().first {
            return storedDrawing
        } else {
            try await actor.insert(DrawingVO.init(bibleTitle: .initialState, section: 1))
            return DrawingVO.init(bibleTitle: .initialState, section: 1)
        }
    }
    
    public func fetch(title: TitleVO) async throws -> [DrawingVO] {
        @Dependency(\.createSwiftDataActor) var createActor
        let actor = try await createActor()
//        let name = title.title.rawValue
//        let chapter = title.chapter
//        let predicate = #Predicate<DrawingVO> {
//            $0.bibleTitle == title
//        }
//        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.section)])
        let storedDrawing: [DrawingVO] = try await actor.fetch()
        Log.debug("fetch Title: \(title)", storedDrawing.count)
        return storedDrawing.filter({ $0.bibleTitle == title })
    }
    
    public func add(item: DrawingVO) async throws {
        @Dependency(\.createSwiftDataActor) var createActor
        let actor = try await createActor()
        try await actor.insert(item)
    }
    
    public func update(item: DrawingVO) async throws {
        @Dependency(\.createSwiftDataActor) var createActor
        let actor = try await createActor()
        try await actor.update(item.id) { (oldValue: DrawingVO) async in
            oldValue.lineData = item.lineData
        }
    }
    
    public func setDrawing(title: TitleVO, to last: Int) async throws {
        @Dependency(\.createSwiftDataActor) var createActor
        let actor = try await createActor()
        let drawings: [DrawingVO] = try await fetch(title: title)
        for drawing in drawings {
            if drawing.section <= last {
                let newDrawing = DrawingVO(bibleTitle: title, section: drawing.section)
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
}

extension DrawingDatabase: DependencyKey {
    public static let liveValue: DrawingDatabase = Self()
    public static let testValue: DrawingDatabase = Self()
}

extension DependencyValues {
    public var drawingData: DrawingDatabase {
        get { self[DrawingDatabase.self] }
        set { self[DrawingDatabase.self] = newValue }
    }
}
