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
    public typealias Item = BibleDrawing
    @Dependency(\.createSwiftDataActor) public var actor
    
    public func fetch() async throws -> BibleDrawing {
        if let storedDrawing: BibleDrawing = try await actor.fetch().first {
            return storedDrawing
        } else {
            try await actor.insert(BibleDrawing.init(bibleTitle: .initialState, verse: 1))
            return BibleDrawing.init(bibleTitle: .initialState, verse: 1)
        }
    }
    
    public func fetch(chapter: BibleChapter) async throws -> [BibleDrawing] {
        let titleName = chapter.title.rawValue
        let chapter = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName
            && $0.titleChapter == chapter
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.verse)])
        let storedDrawing: [BibleDrawing] = try await actor.fetch(descriptor)
        return storedDrawing
    }
    
    public func fetch(title: BibleChapter, verse: Int) async throws -> BibleDrawing? {
        let titleName = title.title.rawValue
        let chapter = title.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName
            && $0.titleChapter == chapter
            && $0.verse == verse
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.verse)])
        let storedDrawing: BibleDrawing? = try await actor.fetch(descriptor).first
        return storedDrawing
    }
    
    public func fetchGrouptedByDate() async throws -> [Date: Int] {
        let allDrawings: [BibleDrawing] = try await actor.fetch()
        let beforeDate = Calendar.current.date(from: DateComponents(year: 2024, month: 12, day: 31))!
        let grouped = Dictionary(
            grouping: allDrawings,
            by: { drawing in
                let date = drawing.updateDate ?? beforeDate
                return Calendar.current.startOfDay(for: date.toLocalTime()) }
        )
        return grouped.mapValues { $0.count }
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
    
    public func setDrawing(title: BibleChapter, to last: Int) async throws {
        let drawings: [BibleDrawing] = try await fetch(chapter: title)
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
        let title = BibleChapter(title: BibleTitle(rawValue: drawing.titleName!)!, chapter: drawing.titleChapter!)
        if (try await fetch(title: title, verse: drawing.verse!)) != nil {
            try await update(item: drawing)
        } else {
            try await actor.insert(drawing)
        }
    }
    
    private func loadChapterPercentage(chapter: BibleChapter) async throws -> Double {
        let drawings: [BibleDrawing] = try await fetch(chapter: chapter)
        guard let lastverse = LastVerseCache.shared.getLastVerse(for: chapter) else { return 0.0 }
        let percentage = Double(drawings.count) / Double(lastverse) * 100.0
        return round(percentage * 100) / 100.0
    }
    
    public func fetchAllChapterPercentage(progressUpadte: ((Double) -> Void)? = nil) async throws -> [BibleChapter: Double] {
        var percentages: [BibleChapter: Double] = [:]
        let totalChapters = BibleTitle.allCases.reduce(0) { $0 + $1.lastChapter }
        let chapterProgressCounter = ChapterProgress()

        await withTaskGroup(of: (BibleChapter, Double)?.self) { group in
            for title in BibleTitle.allCases {
                for chapterNumber in 1...title.lastChapter {
                    let chapter = BibleChapter(title: title, chapter: chapterNumber)
                    
                    group.addTask {
                        do {
                            let percentage = try await self.loadChapterPercentage(chapter: chapter)
                            let completedCount = await chapterProgressCounter.increment()
                            let progress = Double(completedCount) / Double(totalChapters)
                            await MainActor.run {
                                progressUpadte?(progress)
                            }
                            return (chapter, percentage)
                        } catch {
                            return nil
                        }
                    }
                }
                
                for await result in group {
                    if let (chapter, percentage) = result {
                        percentages[chapter] = percentage
                    }
                }
            }
        }
        return percentages
    }
    
    private actor ChapterProgress {
        private(set) var completedChapters: Int = 0
        
        func increment() -> Int {
            completedChapters += 1
            return completedChapters
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
            let database = DrawingDatabase()
            Task {
                for drawing in BibleDrawing.previewData {
                    try await database.add(item: drawing)
                }
            }
            return database
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
