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

public struct DrawingDatabase: Sendable {
    public typealias Item = BibleDrawing
    @Dependency(\.createSwiftDataActor) public var actor
    
    // MARK: - verse 단위 BibleDrawing
    
    /// 한 장의 필사 데이터를 모두 불러옴
    /// - Parameter chapter: 가져올 성경의 이름과 장
    /// - Returns: 해당 장의 필사 데이터
    /// - Note: `verse` 기준 오름차순 정렬(1, 2, 3, ...)로 반환
    public func fetch(chapter: BibleChapter) async throws -> [BibleDrawing] {
        let titleName = chapter.title.rawValue
        let chapter = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName &&
            $0.titleChapter == chapter
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.verse)])
        let storedDrawing: [BibleDrawing] = try await actor.fetch(descriptor)
        return storedDrawing
    }
    
    /// 내부 helper: updateDrawing 에서만 사용되며, id 기준 단건 조회용
    private func fetch(drawing: BibleDrawing) async throws -> BibleDrawing? {
        let id = drawing.id
        let predicate = #Predicate<BibleDrawing> {
            $0.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.verse)])
        let storedDrawing: BibleDrawing? = try await actor.fetch(descriptor).first
        return storedDrawing
    }
    
    /// 해당 절의 필사 데이터를 모두 가져옴
    /// - Parameters:
    ///   - chapter: 해당 성경의 이름과 장
    ///   - verse: 절 번호
    /// - Returns: 해당 절에 저장된 모든 필사 데이터를 반환
    /// - Note: `updateDate` 기준 내림차순 정렬(가장 최근 데이터가 먼저)으로 반환되며,
    ///         비어 있을 경우 빈 배열(`[]`) 반환.
    public func fetchDrawings(chapter: BibleChapter, verse: Int) async throws -> [BibleDrawing] {
        let titleName = chapter.title.rawValue
        let chapter = chapter.chapter
        let predicate = #Predicate<BibleDrawing> {
            $0.titleName == titleName
            && $0.titleChapter == chapter
            && $0.verse == verse
        }
        let descriptor = FetchDescriptor(predicate: predicate,
                                         sortBy: [SortDescriptor(\.updateDate, order: .reverse)])
        let storedDrawing: [BibleDrawing] = try await actor.fetch(descriptor)
        Log.debug("Drew Log Count:", storedDrawing.count)
        return storedDrawing
    }

    public func fetchDrawings(date: Date) async throws -> [BibleDrawing]? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay)!

        let predicate = #Predicate<BibleDrawing> {
            if let updateDate = $0.updateDate {
                  return updateDate >= startOfDay && updateDate <= endOfDay
              } else {
                  return false
              }
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let storedDrawing: [BibleDrawing]? = try await actor.fetch(descriptor)
        Log.debug("Drew Log Count:", storedDrawing?.count)
        return storedDrawing
    }
    
    /// 여러 절의 필사 데이터를 한 번에 업데이트(update)
    /// - Parameter requests: 각 절에 대한 업데이트 정보를 담은 요청 배열
    /// - Important: 동일한 (title, verse)에 대해서는 `fetchDrawings`를 통해
    ///   가장 최근 데이터(대표 Drawing)를 찾아 `lineData`와 `updateDate`만 갱신.
    ///   기존 데이터가 없을 경우 새 `BibleDrawing`을 생성해 저장.
    public func updateDrawings(requests: [DrawingUpdateRequest]) async {
        for req in requests {
            do {
                // 해당 verse 에 대한 기존 drawing fetch
                let existing = try await fetchDrawings(chapter: req.chapter, verse: req.verse).mainDrawing()

                if let existing {
                    // 기존 데이터 업데이트
                    let id = existing.persistentModelID
                    try await actor.update(id) { (old: BibleDrawing) async in
                        old.lineData = req.updateLineData
                        old.updateDate = req.updateDate

                        // base size는 요청에 값이 있을 때만 반영 (nil이면 기존값 유지)
                        if let bw = req.baseWidth { old.baseWidth = bw }
                        if let bh = req.baseHeight { old.baseHeight = bh }
                    }
                    Log.debug("updated drawing verse:", req.verse)
                } else {
                    // 존재하지 않으면 새로 생성
                    let new = BibleDrawing(
                        bibleTitle: req.chapter,
                        verse: req.verse,
                        lineData: req.updateLineData,
                        updateDate: req.updateDate
                    )
                    // base size는 요청에 값이 있을 때만 세팅
                    if let bw = req.baseWidth { new.baseWidth = bw }
                    if let bh = req.baseHeight { new.baseHeight = bh }
                    try await actor.insert(new)
                    Log.debug("inserted new drawing verse:", req.verse)
                }
            } catch {
                Log.error("❌ updateDrawings failed:", error)
            }
        }
    }
    
    /// 특정 절에서 어떤 Drawing이 isPresent인지 저장.
    /// - Parameters:
    ///   - chapter: 성경의 이름과 장
    ///   - verse: 절 번호
    ///   - presentID: isPresent = true 로 표시할 Drawing의 ID
    public func updatePresentDrawing(
        chapter: BibleChapter,
        verse: Int,
        presentID: PersistentIdentifier
    ) async {
        do {
            let drawings = try await fetchDrawings(chapter: chapter, verse: verse)
            for drawing in drawings {
                let id = drawing.persistentModelID
                try await actor.update(id) { (old: BibleDrawing) async in
                    old.isPresent = (old.persistentModelID == presentID)
                }
            }
            Log.debug(" updatePresentDrawing verse:", verse)
        } catch {
            Log.error("❌ updatePresentDrawing failed:", error)
        }
    }
    
    
    // MARK: - Page 단위 BibleDrawing
    
    /// 한 장 전체의 페이지 단위 필사 데이터(BiblePageDrawing)를 불러옴.
    /// - Parameter chapter: 가져올 성경의 이름과 장
    /// - Returns: 해당 장의 페이지 전체 필사 데이터 (없으면 nil)
    /// - Note: 정렬 조건은 없으며, 조건에 매칭되는 첫 번째 레코드만 반환.
    public func fetchPageDrawing(chapter: BibleChapter) async throws -> BiblePageDrawing? {
        let titleName = chapter.title.rawValue
        let chapter = chapter.chapter
        let predicate = #Predicate<BiblePageDrawing> {
            $0.titleName == titleName &&
            $0.titleChapter == chapter
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let stored: BiblePageDrawing? = try await actor.fetch(descriptor).first
        return stored
    }
    
    /// 페이지 단위 full PKDrawing 저장/업데이트
    /// - Parameters:
    ///   - title: 저장할 성경의 이름과 장
    ///   - fullLineData: 페이지 전체 기준 PKDrawing.dataRepresentation()
    ///   - drawingVersion: 좌표계/인코딩 버전을 나타내는 버전 값
    ///   - updateDate: 업데이트 일시 (기본값: 현재 시각)
    public func upsertPageDrawing(
        chapter: BibleChapter,
        fullLineData: Data,
        updateDate: Date = .now
    ) async {
        do {
            if let existing = try await fetchPageDrawing(chapter: chapter) {
                // 기존 페이지 Drawing 업데이트
                let id = existing.persistentModelID
                try await actor.update(id) { (old: BiblePageDrawing) async in
                    old.fullLineData = fullLineData
                    old.updateDate = updateDate
                }
                Log.debug("🔄 updated page drawing:", chapter)
            } else {
                // 없으면 새로 생성
                let page = BiblePageDrawing(
                    bibleTitle: chapter,
                    fullLineData: fullLineData,
                    updateDate: updateDate
                )
                try await actor.insert(page)
                Log.debug(" inserted page drawing:", chapter)
            }
        } catch {
            Log.error("❌ upsertPageDrawing failed:", error)
        }
    }
    
    /// 최근 range 사이에 업데이트 된 drawing을 최신순으로 반환
    public func fetchDrawings(in range: DateInterval) async throws -> [BibleDrawing] {
        let predicate = #Predicate<BibleDrawing> {
            if let updateDate = $0.updateDate {
                return updateDate >= range.start && updateDate < range.end
            } else {
                return false
            }
        }

        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updateDate, order: .reverse)]
        )

        return try await actor.fetch(descriptor)
    }
    
    /// 최근 필사 Verse 리스트용 (최신순, 제한)
    public func fetchRecentDrawings(limit: Int) async throws -> [BibleDrawing] {
        guard limit > 0 else { return [] }

        let predicate = #Predicate<BibleDrawing> {
            $0.updateDate != nil
        }

        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updateDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        return try await actor.fetch(descriptor)
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
