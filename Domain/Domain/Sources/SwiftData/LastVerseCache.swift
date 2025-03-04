//
//  LastVerseCache.swift
//  Domain
//
//  Created by 이택성 on 1/24/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Core
import Foundation
import Resources

import Dependencies

public actor LastVerseCache {
    private var lastVerses: [BibleChapter: Int] = [:]
    private var progressContinuation: AsyncStream<Double>.Continuation?
    private var lastEmittedProgress: Double = 0.0
    public let progressStream: AsyncStream<Double>
    
    public init() {
        let (stream, continuation) = AsyncStream<Double>.makeStream()
        self.progressStream = stream
        self.progressContinuation = continuation
    }
    
    private func cacheFileURL() -> URL {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory,
                                                         in: .userDomainMask).first!
        return documentDirectory.appendingPathComponent("LastVersesCache.json")
    }
    
    
    public func loadCache() async {
        if let cache = await loadCacheFromFile() {
            lastVerses = cache
            progressContinuation?.yield(1.0)
            progressContinuation?.finish()
        } else {
            await setLastVersesCache()
        }
        Log.debug("캐싱 완료")
    }
    
    public func loadCacheFromFile() async -> [BibleChapter: Int]? {
        let url = cacheFileURL()
        do {
            let data = try await Task.detached {
                try Data(contentsOf: url)
            }.value
            return try JSONDecoder().decode([BibleChapter: Int].self, from: data)
        } catch {
            Log.error("no cache file found")
            return nil
        }
    }
    
    private func saveCacheToFile() async {
        let url = cacheFileURL()
        do {
            let data = try JSONEncoder().encode(lastVerses)
            try await Task.detached {
                try data.write(to: url)
            }.value
        } catch {
            Log.error("Failed to save LastVerseCache: \(error)")
        }
    }
    
    private func setLastVersesCache() async {
        var calculatedData: [BibleChapter: Int] = [:]
        let totalChapters = BibleTitle.allCases.reduce(0) { $0 + $1.lastChapter }
        let progressCounter = ChapterProgress()
        
        let bibleChapters = BibleTitle.allCases.flatMap { title in
            (1...title.lastChapter).map { chapter in
                BibleChapter(title: title, chapter: chapter)
            }
        }
        Log.debug("총 캐싱해야 할 챕터 수: \(bibleChapters.count)")

        await withTaskGroup(of: (BibleChapter, Int?).self) { group in
            for bibleChapter in bibleChapters {
                group.addTask {
                    do {
                        let lastVerse = try await self.fetchLastVerse(for: bibleChapter)
                        let completed = await progressCounter.increment()
                        let progress = Double(completed) / Double(totalChapters)

                        await self.emitProgressIfNeeded(progress)
                        return (bibleChapter, lastVerse)
                    } catch {
                        Log.error(error.localizedDescription, bibleChapter)
                        return (bibleChapter, nil)
                    }
                }
            }
            
            for await (bibleChapter, lastVerse) in group {
                guard let lastVerse else { continue }
                calculatedData[bibleChapter] = lastVerse
            }
        }
        
        lastVerses = calculatedData
        await saveCacheToFile()
        progressContinuation?.yield(1.0)
        progressContinuation?.finish()
    }
    
    private func fetchLastVerse(for chapter: BibleChapter) async throws(LastVerseCacheError) -> Int {
        let encodingEUCKR = CFStringConvertEncodingToNSStringEncoding(0x0422)
        guard let textPath = ResourcesResources.bundle.path(forResource: chapter.title.rawValue,
                                                            ofType: nil)
        else { throw .textPathError }
        
        do {
            let bibleText = try await Task.detached {
                try String(contentsOfFile: textPath,
                           encoding: String.Encoding(rawValue: encodingEUCKR))
            }.value
                    
            let chapterSentences = bibleText
                .components(separatedBy: CharacterSet.newlines)
                .filter { line in
                    let components = line.components(separatedBy: ":")
                    guard components.count >= 2,
                          let chapterNum = components.first,
                          let chapterInt = Int(chapterNum) else {
                        return false
                    }
                    return chapterInt == chapter.chapter
                }
            
            guard let verseComponents = chapterSentences.last?.components(separatedBy: ":"),
                  verseComponents.count >= 2
            else { throw LastVerseCacheError.invalidChapterNumberError }
            
            let lastVerseStr = verseComponents[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let component = lastVerseStr.split(separator: " ")
            if let verseNum = component.first, let lastVerse = Int(verseNum) {
                return lastVerse
            } else {
                throw LastVerseCacheError.invalidChapterNumberError
            }
        } catch {
            throw .readingFileError
        }
    }
    
    public func getLastVerse(for chapter: BibleChapter) async -> Int? {
        return lastVerses[chapter]
    }
    
    private func emitProgressIfNeeded(_ progress: Double) {
        let progressIncrease = (progress - lastEmittedProgress) * 100
        if progressIncrease >= 1.0 {
            lastEmittedProgress = progress
            self.progressContinuation?.yield(progress)
        }
    }
    
    private actor ChapterProgress {
        private var completedChapters: Int = 0
        
        func increment() -> Int {
            completedChapters += 1
            return completedChapters
            
        }
    }
    
    enum LastVerseCacheError: Error {
        case textPathError
        case readingFileError
        case invalidChapterNumberError
    }
}

extension LastVerseCache: DependencyKey {
    public static var liveValue: LastVerseCache = LastVerseCache()
    public static var testValue: LastVerseCache = LastVerseCache()
    public static var previewValue: LastVerseCache = LastVerseCache()
}

extension DependencyValues {
    public var lastVerseCache: LastVerseCache {
        get { self[LastVerseCache.self] }
        set { self[LastVerseCache.self] = newValue }
    }
}
