//
//  FavoriteVerseRepository.swift
//  Domain
//
//  Created by Claude on 9/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

// MARK: - 즐겨찾기 식별 · 항목 (시안 N)

/// 즐겨찾기 한 항목의 식별 — **번역본 · 권 · 장 · 절마다 하나**다.
///
/// CloudKit 은 unique 제약을 허용하지 않아 같은 키의 행이 여럿 저장될 수 있다. 저장소는 이 키로 합쳐 한 항목으로 돌려준다.
public struct FavoriteVerseKey: Hashable, Sendable {
    public let chapter: BibleChapter
    public let verse: Int
    public let translation: Translation

    public init(chapter: BibleChapter, verse: Int, translation: Translation = .NKRV) {
        self.chapter = chapter
        self.verse = verse
        self.translation = translation
    }
}

/// 즐겨찾기 한 항목 — **추가한 당시의 본문과 필기**다 (2026-09-15 결정).
///
/// 원래 절의 필사 행을 참조하지 않는다. 이후 그 절을 지우거나 다시 써도 이 값은 바뀌지 않는다.
public struct FavoriteVerseSnapshot: Hashable, Sendable, Identifiable {
    public var id: FavoriteVerseKey { key }

    public let key: FavoriteVerseKey
    /// 추가할 때의 본문.
    public let sentence: String
    /// 추가할 때의 필기(`PKDrawing.dataRepresentation()`). 획이 없던 절이면 nil 이다.
    public let lineData: Data?
    /// 추가한 시각. 목록은 이 값의 최신순이다.
    public let createdDate: Date

    public init(key: FavoriteVerseKey, sentence: String, lineData: Data?, createdDate: Date) {
        self.key = key
        self.sentence = sentence
        self.lineData = lineData
        self.createdDate = createdDate
    }
}

// MARK: - 저장소

/// 즐겨찾기의 SwiftData 접근 경로. Feature 는 이 계약만 알고 `FavoriteVerse` 모델을 만지지 않는다.
///
/// 즐겨찾기를 해제해도 원래 필사나 이전 필사 기록은 지우지 않는다 — 이 저장소는 `BibleDrawing` 을 건드리지 않는다.
public protocol FavoriteVerseRepository: Sendable {
    /// 장에서 즐겨찾기한 절 번호. 필사 화면의 절 메뉴 문구와 절 번호 아래 별 표시가 읽는다.
    /// - Parameters:
    ///   - chapter: 대상 장.
    ///   - translation: 대상 번역본.
    func favoriteVerses(in chapter: BibleChapter, translation: Translation) async throws -> Set<Int>

    /// 모든 즐겨찾기 — 최근 추가순이고 키마다 하나다(같은 키가 여럿이면 가장 최근 것).
    func favorites() async throws -> [FavoriteVerseSnapshot]

    /// 즐겨찾기를 저장한다. 같은 키가 이미 있으면 그 행을 이 값으로 바꾸고 나머지 중복 행은 지운다 — 한 트랜잭션.
    ///
    /// 해제를 되돌릴 때도 쓴다. 해제한 항목을 그대로 넘기면 추가 시각까지 같아 목록의 원래 자리로 돌아간다.
    func save(_ favorite: FavoriteVerseSnapshot) async throws

    /// 키가 같은 행을 모두 지운다. 없으면 아무것도 하지 않는다.
    func remove(_ key: FavoriteVerseKey) async throws
}

private enum FavoriteVerseRepositoryKey: DependencyKey {
    static let liveValue: any FavoriteVerseRepository = SwiftDataFavoriteVerseRepository()
    /// 테스트 기본값은 **아무 저장소도 건드리지 않는다.** 즐겨찾기를 확인하는 테스트는 자기 저장소를 주입한다.
    ///
    /// SwiftData 테스트 actor(`createSwiftDataActor.testValue`)를 기본값으로 쓰지 않는 이유 — 그 actor 는 프로세스에 하나이고
    /// 처음 깨운 테스트의 컨테이너에 묶인다. 장을 여는(`setSentence`) 테스트마다 즐겨찾기 조회가 그 actor 를 먼저 깨우면,
    /// 검증용 컨테이너를 따로 여는 `DrawingErasePersistenceTesting` 이 다른 저장소를 보고 실패한다(2026-09-15 전체 회귀에서 관측).
    static let testValue: any FavoriteVerseRepository = EmptyFavoriteVerseRepository()
    static var previewValue: any FavoriteVerseRepository {
        withDependencies {
            $0.createSwiftDataActor = .previewValue
        } operation: {
            SwiftDataFavoriteVerseRepository()
        }
    }
}

/// 비어 있는 즐겨찾기 저장소 — 읽으면 없고, 쓰면 버린다. 테스트 기본값이다(`BibleTextClient` 의 테스트값과 같은 자리).
private struct EmptyFavoriteVerseRepository: FavoriteVerseRepository {
    func favoriteVerses(in chapter: BibleChapter, translation: Translation) async throws -> Set<Int> {
        []
    }

    func favorites() async throws -> [FavoriteVerseSnapshot] {
        []
    }

    func save(_ favorite: FavoriteVerseSnapshot) async throws {}

    func remove(_ key: FavoriteVerseKey) async throws {}
}

public extension DependencyValues {
    var favoriteVerseRepository: any FavoriteVerseRepository {
        get { self[FavoriteVerseRepositoryKey.self] }
        set { self[FavoriteVerseRepositoryKey.self] = newValue }
    }
}
