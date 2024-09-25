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
    private var actor = SwiftDatabaseActor(modelContainer: PersistentCloudKitContainer.shared.container)

    public func fetch() async throws -> DrawingVO {
        let drawing = Task.detached {
            if let storedDrawing: DrawingVO = try await actor.fetch().first {
                return storedDrawing
            } else {
                try await actor.insert(DrawingVO.init(bibleTitle: .initialState, section: 1))
                return DrawingVO.init(bibleTitle: .initialState, section: 1)
            }
        }
        return try await drawing.value
    }
    
    public func fetch(title: TitleVO) async throws -> [DrawingVO] {
        let drawings = Task.detached {
            let titleName = title.title.rawValue
            let chapter = title.chapter
            let predicate = #Predicate<DrawingVO> {
                $0.titleName == titleName
                && $0.titleChapter == chapter
            }
            let descriptor = FetchDescriptor(predicate: predicate,
                                             sortBy: [SortDescriptor(\.section)])
            let storedDrawing: [DrawingVO] = try await actor.fetch(descriptor)
            storedDrawing.forEach {
                Log.debug("fetchTitle \($0.titleName). \($0.titleChapter)", $0.lineData)
            }
            Log.debug("fetch Title: \(title)", storedDrawing.count)
            return storedDrawing
        }
        return try await drawings.value
    }
    
    public func fetch(title: TitleVO, section: Int) async throws -> DrawingVO? {
        let drawings = Task.detached {
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
        return try await drawings.value
    }
    
    public func add(item: DrawingVO) async throws {
        Task.detached {
            try await actor.insert(item)
        }
    }
    
    public func update(item: DrawingVO) async throws {
        Task.detached {
            try await actor.update(item.id) { (oldValue: DrawingVO) async in
                oldValue.lineData = item.lineData
            }
        }
    }
    
    public func setDrawing(title: TitleVO, to last: Int) async throws {
        Task.detached {
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
    }
    
    public func updateDrawing(drawing: DrawingVO) async throws {
        Task.detached {
            let title = TitleVO(title: BibleTitle(rawValue: drawing.titleName!)!, chapter: drawing.titleChapter!)
            if let storedDrawing = try await fetch(title: title, section: drawing.section!) {
                try await update(item: drawing)
            } else {
                try await actor.insert(drawing)
            }
            Log.debug("update drawing", drawing)
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
