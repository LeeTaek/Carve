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
    
    public func fetch() async throws -> DrawingVO {
        if let storedDrawing: DrawingVO = try await actor.fetch().first {
            return storedDrawing
        } else {
            try await actor.insert(DrawingVO.init(bibleTitle: .initialState, section: 1))
            return DrawingVO.init(bibleTitle: .initialState, section: 1)
        }
    }
    
    public func fetch(chapter: BibleChapter) async throws -> [DrawingVO] {
        let titleName = chapter.title.rawValue
        let chapter = chapter.chapter
        let predicate = #Predicate<DrawingVO> {
            $0.titleName == titleName
            && $0.titleChapter == chapter
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.section)])
        let storedDrawing: [DrawingVO] = try await actor.fetch(descriptor)
        return storedDrawing
    }
    
    public func fetch(title: BibleChapter, section: Int) async throws -> DrawingVO? {
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
    
    public func fetchGrouptedByDate() async throws -> [Date: Int] {
        let allDrawings: [DrawingVO] = try await actor.fetch()
        let beforeDate = Calendar.current.date(from: DateComponents(year: 2024, month: 12, day: 31))!
        let grouped = Dictionary(
            grouping: allDrawings,
            by: { drawing in
                let date = drawing.updateDate ?? beforeDate
                return Calendar.current.startOfDay(for: date.toLocalTime()) }
        )
        return grouped.mapValues { $0.count }
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
    
    public func setDrawing(title: BibleChapter, to last: Int) async throws {
        let drawings: [DrawingVO] = try await fetch(chapter: title)
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
        let title = BibleChapter(title: BibleTitle(rawValue: drawing.titleName!)!, chapter: drawing.titleChapter!)
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
    }
    
    private func loadChapterPercentage(chapter: BibleChapter, cache: LastVerseCache) async throws -> Double {
        let drawings: [DrawingVO] = try await fetch(chapter: chapter)
        guard let lastverse = await cache.getLastVerse(for: chapter) else { return 0.0 }
        let percentage = Double(drawings.count) / Double(lastverse) * 100.0
        return round(percentage * 100) / 100.0
    }
    
    public func fetchAllChapterPercentage(progressUpdate: ((Double) -> Void)? = nil) async throws -> [BibleChapter: Double] {
        var percentages: [BibleChapter: Double] = [:]
        let totalChapters = BibleTitle.allCases.reduce(0) { $0 + $1.lastChapter }
        let chapterProgressCounter = ChapterProgress()
        let lastVerseCache = LastVerseCache()
        
        var cacheProgress: Double = 0.0
        var taskGroupProgress: Double = 0.0
        
        Task {
            await lastVerseCache.loadCache()
        }
        
        Task.detached {
            for await progress in lastVerseCache.progressStream {
                cacheProgress = progress
                let combinedProgress = self.combineProgress(cacheProgress: cacheProgress, taskGroupProgress: taskGroupProgress)

                await MainActor.run {
                    progressUpdate?(combinedProgress)
                }
                await Task.yield()
            }
        }
        
        await withTaskGroup(of: (BibleChapter, Double)?.self) { group in
            for title in BibleTitle.allCases {
                for chapterNumber in 1...title.lastChapter {
                    let chapter = BibleChapter(title: title, chapter: chapterNumber)
                    
                    group.addTask {
                        do {
                            let percentage = try await self.loadChapterPercentage(chapter: chapter,
                                                                                  cache: lastVerseCache)
                            let completedCount = await chapterProgressCounter.increment()
                            taskGroupProgress = Double(completedCount) / Double(totalChapters)
                            let combinedProgress = self.combineProgress(cacheProgress: cacheProgress,
                                                                        taskGroupProgress: taskGroupProgress)
                            await MainActor.run {
                                progressUpdate?(combinedProgress)
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
    
    private func combineProgress(cacheProgress: Double, taskGroupProgress: Double) -> Double {
        return (cacheProgress * 0.5) + (taskGroupProgress * 0.5)
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
                for drawing in DrawingVO.previewData {
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
