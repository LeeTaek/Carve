//
//  SwiftDataFavoriteVerseRepository.swift
//  Domain
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import SwiftData

import Dependencies

/// `FavoriteVerseRepository` 의 SwiftData 구현.
///
/// 모든 읽기 · 쓰기는 `SwiftDatabaseActor` 안에서 일어나고, 쓰기는 actor 메서드 하나가 한 트랜잭션이다 —
/// 변경을 모아 마지막에 `save()` 1회, 실패하면 `rollback()` (`SwiftDataDrawingRepository` 와 같은 경계).
public struct SwiftDataFavoriteVerseRepository: FavoriteVerseRepository {
    private let actor: SwiftDatabaseActor

    /// - Parameter actor: 사용할 actor. 생략하면 현재 의존성의 actor.
    public init(actor: SwiftDatabaseActor? = nil) {
        if let actor {
            self.actor = actor
        } else {
            @Dependency(\.createSwiftDataActor) var injected
            self.actor = injected
        }
    }

    public func favoriteVerses(in chapter: BibleChapter, translation: Translation) async throws -> Set<Int> {
        try await actor.loadFavoriteVerses(in: chapter, translation: translation)
    }

    public func favorites() async throws -> [FavoriteVerseSnapshot] {
        try await actor.loadFavorites()
    }

    public func save(_ favorite: FavoriteVerseSnapshot) async throws {
        try await actor.saveFavorite(favorite)
    }

    public func remove(_ key: FavoriteVerseKey) async throws {
        try await actor.removeFavorites(key)
    }
}

// MARK: - actor 안의 트랜잭션

extension SwiftDatabaseActor {
    /// 장에서 즐겨찾기한 절 번호를 읽는다.
    /// - Parameters:
    ///   - chapter: 대상 장.
    ///   - translation: 대상 번역본.
    /// - Returns: 절 번호 집합.
    public func loadFavoriteVerses(in chapter: BibleChapter, translation: Translation) throws -> Set<Int> {
        let rows = try favoriteRows(in: chapter)
        return Set(rows.filter { ($0.translation ?? .NKRV) == translation }.compactMap(\.verse))
    }

    /// 모든 즐겨찾기를 최근 추가순으로 읽는다. 같은 키의 행이 여럿이면 가장 최근 행 하나만 남긴다.
    /// - Returns: 키마다 하나인 즐겨찾기.
    public func loadFavorites() throws -> [FavoriteVerseSnapshot] {
        let descriptor = FetchDescriptor<FavoriteVerse>(sortBy: Self.newestFirst)
        var seen: Set<FavoriteVerseKey> = []
        return try modelContext.fetch(descriptor).compactMap { row in
            guard let favorite = row.snapshot, seen.insert(favorite.key).inserted else { return nil }
            return favorite
        }
    }

    /// 즐겨찾기를 저장한다. 같은 키의 가장 최근 행을 이 값으로 바꾸고, 다른 기기가 따로 만든 중복 행은 지운다.
    /// - Parameter favorite: 저장할 항목.
    public func saveFavorite(_ favorite: FavoriteVerseSnapshot) throws {
        do {
            let rows = try favoriteRows(for: favorite.key)
            if let row = rows.first {
                row.sentence = favorite.sentence
                row.lineData = favorite.lineData
                row.createdDate = favorite.createdDate
                for duplicate in rows.dropFirst() {
                    modelContext.delete(duplicate)
                }
            } else {
                modelContext.insert(FavoriteVerse(
                    chapter: favorite.key.chapter,
                    verse: favorite.key.verse,
                    translation: favorite.key.translation,
                    sentence: favorite.sentence,
                    lineData: favorite.lineData,
                    createdDate: favorite.createdDate
                ))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// 키가 같은 즐겨찾기 행을 모두 지운다. 없으면 쓰기 0건이다.
    /// - Parameter key: 해제할 항목.
    public func removeFavorites(_ key: FavoriteVerseKey) throws {
        do {
            let rows = try favoriteRows(for: key)
            guard !rows.isEmpty else { return }
            for row in rows {
                modelContext.delete(row)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: 내부

    /// 최근 추가순. 추가 시각이 같으면 행 식별자 사전순으로 결정한다.
    private static var newestFirst: [SortDescriptor<FavoriteVerse>] {
        [SortDescriptor(\.createdDate, order: .reverse), SortDescriptor(\.favoriteID)]
    }

    /// 장의 즐겨찾기 행(최근 추가순). 번역본은 술어에 넣지 않고 메모리에서 거른다 — `Translation` 은 Codable 열거형이라
    /// 술어로 비교하는 경로를 확인하지 않았고, 한 장의 즐겨찾기는 몇 행뿐이다.
    private func favoriteRows(in chapter: BibleChapter) throws -> [FavoriteVerse] {
        let titleName = chapter.title.rawValue
        let chapterNumber = chapter.chapter
        let predicate = #Predicate<FavoriteVerse> {
            $0.titleName == titleName && $0.titleChapter == chapterNumber
        }
        return try modelContext.fetch(FetchDescriptor(predicate: predicate, sortBy: Self.newestFirst))
    }

    private func favoriteRows(for key: FavoriteVerseKey) throws -> [FavoriteVerse] {
        try favoriteRows(in: key.chapter).filter {
            $0.verse == key.verse && ($0.translation ?? .NKRV) == key.translation
        }
    }
}

// MARK: - 행 → 도메인 값

extension DrawingSchemaV5.FavoriteVerse {
    /// 권 · 장 · 절을 해석할 수 없는 행(알 수 없는 권 이름 등)은 nil — 목록에 올리지 않는다.
    var snapshot: FavoriteVerseSnapshot? {
        guard let titleName, let title = BibleTitle(rawValue: titleName),
              let titleChapter, let verse else { return nil }
        return FavoriteVerseSnapshot(
            key: FavoriteVerseKey(
                chapter: BibleChapter(title: title, chapter: titleChapter),
                verse: verse,
                translation: translation ?? .NKRV
            ),
            sentence: sentence ?? "",
            lineData: lineData,
            createdDate: createdDate ?? .distantPast
        )
    }
}
