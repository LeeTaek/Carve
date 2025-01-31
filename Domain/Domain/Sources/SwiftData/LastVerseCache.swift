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

public class LastVerseCache {
    static let shared = LastVerseCache()
    private var lastVerses: [BibleChapter: Int] = [:]
    
    private init() {
        loadCache()
    }
    
    private func cacheFileURL() -> URL {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory,
                                                         in: .userDomainMask).first!
        return documentDirectory.appendingPathComponent("LastVersesCache.json")
    }
    
    
    private func loadCache() {
        if let cache = loadCacheFromFile() {
            lastVerses = cache
            Log.debug("✅ 캐시 저장 후 재로드 성공: \(lastVerses.count) 개의 데이터")

        } else {
            setLastVersesCache()
        }
    }
    
    private func loadCacheFromFile() -> [BibleChapter: Int]? {
        let url = cacheFileURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([BibleChapter: Int].self, from: data)
    }
    
    private func saveCacheToFile() {
        let url = cacheFileURL()
        if let data = try? JSONEncoder().encode(lastVerses) {
            try? data.write(to: url)
        }
    }
    
    private func setLastVersesCache() {
        var calculatedData: [BibleChapter: Int] = [:]
        for title in BibleTitle.allCases {
            for chapter in 1...title.lastChapter {
                let bibleChapter = BibleChapter(title: title, chapter: chapter)
                
                do {
                    let lastVerse = try fetchLastVerse(for: bibleChapter)
                    calculatedData[bibleChapter] = lastVerse
                } catch {
                    Log.debug(error.localizedDescription)
                }
            }
        }
        lastVerses = calculatedData
        saveCacheToFile()
    }
    
    private func fetchLastVerse(for chapter: BibleChapter) throws(LastVerseCacheError) -> Int {
        let encodingEUCKR = CFStringConvertEncodingToNSStringEncoding(0x0422)
        guard let textPath = ResourcesResources.bundle.path(forResource: chapter.title.rawValue,
                                                            ofType: nil)
        else {
            throw .textPathError
        }
        
        do {
            let bibleText = try String(contentsOfFile: textPath,
                                       encoding: String.Encoding(rawValue: encodingEUCKR))
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
            else {
                throw LastVerseCacheError.invalidChapterNumberError
            }
            
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
    
    public func getLastVerse(for chapter: BibleChapter) -> Int? {
        return lastVerses[chapter]
    }
    
    enum LastVerseCacheError: Error {
        case textPathError
        case readingFileError
        case invalidChapterNumberError
    }
}
