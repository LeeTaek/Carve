//
//  DrawingActivityRepository.swift
//  Domain
//
//  Created by Claude on 9/28/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

// MARK: - 필사 활동 스냅샷

/// 필사 한 행의 활동 기록 — 차트가 날짜별 · 장별로 세는 데 필요한 값만 옮긴 스냅샷이다.
///
/// `BibleDrawing` 모델을 Feature 로 넘기지 않기 위한 값이다. 필기(`lineData`)는 담지 않는다.
/// 차트 · 최근 기록 조회는 모든 필사책 · 번역본의 행을 담는다(필사책 결정 10 — 합산) — 필사책 · 장 · 번역본은 `page` · `chapter` · `translation` 으로 읽는다.
public struct DrawingActivity: Equatable, Sendable {
    /// 마지막으로 고친 시각.
    public let updateDate: Date?
    /// 행에 저장된 권 이름 그대로 — 개역개정은 `BibleTitle.rawValue`, KJV · BSB 는 번역본 접두, 기본이 아닌 필사책은 그 앞에 필사책 접두가 붙는다(`StoredBookKey`).
    /// 권 · 번역본 · 필사책은 이 문자열을 직접 풀지 말고 `page` · `chapter` 로 읽는다.
    public let titleName: String?
    /// 장 번호.
    public let titleChapter: Int?
    /// 절 번호.
    public let verse: Int?

    public init(updateDate: Date?, titleName: String?, titleChapter: Int?, verse: Int?) {
        self.updateDate = updateDate
        self.titleName = titleName
        self.titleChapter = titleChapter
        self.verse = verse
    }

    /// 역할: 필사책 안의 장(번역본 포함)으로 활동을 만든다 — 저장 행과 같은 `titleName` 을 `StoredBookKey.titleName(for: page)` 로 짓는다.
    /// 입력 · 출력: 고친 시각 · 필사책과 장 · 절 → 활동. 부작용 없음.
    public init(updateDate: Date?, page: NotebookChapter, verse: Int?) {
        self.init(
            updateDate: updateDate,
            titleName: StoredBookKey.titleName(for: page),
            titleChapter: page.chapter.chapter,
            verse: verse
        )
    }

    /// 역할: **기본 필사책**의 장(번역본 포함)으로 활동을 만든다 — `init(updateDate:page:verse:)` 로 넘긴다.
    /// 입력 · 출력: 고친 시각 · 장 · 절 → 활동. 부작용 없음.
    /// - Note: 뜻은 「기본 필사책」 이다. 새 코드는 `init(updateDate:page:verse:)` 를 쓴다. t4 에서 지운다.
    public init(updateDate: Date?, chapter: BibleChapter, verse: Int?) {
        self.init(updateDate: updateDate, page: NotebookChapter(notebook: .default, chapter: chapter), verse: verse)
    }

    /// 행의 필사책 · 권 · 장 · 번역본 — `titleName` 을 `StoredBookKey.decodeRow` 로 푼다. 모든 필사책의 행이 풀린다.
    /// 권 이름을 모르거나 필사책 접두가 깨졌거나(`decodeRow` 가 nil) 장 번호가 없으면 nil 이다 — 호출부는 지금처럼 건너뛴다.
    public var page: NotebookChapter? {
        guard let titleName, let titleChapter, let key = StoredBookKey.decodeRow(titleName) else { return nil }
        return key.page(chapter: titleChapter)
    }

    /// 행의 권 · 장 · 번역본 — `page` 의 장이다. 필사책은 가리지 않는다(차트 · 주간 요약은 모든 필사책 합산, 결정 10).
    public var chapter: BibleChapter? {
        page?.chapter
    }

    /// 행의 번역본 — 번역본 접두가 없으면 개역개정이다. 권 이름을 모르면(`decodeRow` 가 nil) nil 이다. 장 번호가 없어도 읽힌다.
    public var translation: Translation? {
        titleName.flatMap(StoredBookKey.decodeRow)?.translation
    }
}

// MARK: - 저장소

/// 필사 활동 조회 경로. 차트는 이 계약만 알고 `BibleDrawing` 모델을 만지지 않는다.
public protocol DrawingActivityRepository: Sendable {
    /// 기간 안에 고친 필사 활동 — 최신순이다. 고친 시각이 없는 행은 빠진다.
    /// - Parameter range: 조회 기간(시작 포함, 끝 제외).
    func activities(in range: DateInterval) async throws -> [DrawingActivity]

    /// 최근에 고친 필사 활동 — 최신순으로 `limit` 개까지다. `limit` 이 0 이하면 비어 있다.
    func recentActivities(limit: Int) async throws -> [DrawingActivity]
}

private enum DrawingActivityRepositoryKey: DependencyKey {
    static let liveValue: any DrawingActivityRepository = SwiftDataDrawingActivityRepository()
    /// 테스트 기본값은 **아무 저장소도 건드리지 않는다.** 조회 결과를 확인하는 테스트는 자기 저장소를 주입한다.
    ///
    /// SwiftData 테스트 actor(`createSwiftDataActor.testValue`)를 기본값으로 쓰지 않는 이유 — 그 actor 는 프로세스에 하나이고
    /// 처음 깨운 테스트의 컨테이너에 묶인다. 차트를 여는 테스트가 그 actor 를 먼저 깨우면, 검증용 컨테이너를 따로 여는
    /// 테스트(`DrawingErasePersistenceTesting` 등)가 다른 저장소를 보고 실패한다(`FavoriteVerseRepository` 와 같은 이유).
    static let testValue: any DrawingActivityRepository = EmptyDrawingActivityRepository()
    static var previewValue: any DrawingActivityRepository {
        withDependencies {
            $0.createSwiftDataActor = .previewValue
        } operation: {
            SwiftDataDrawingActivityRepository()
        }
    }
}

/// 비어 있는 필사 활동 저장소 — 읽으면 없다. 테스트 기본값이다.
private struct EmptyDrawingActivityRepository: DrawingActivityRepository {
    func activities(in range: DateInterval) async throws -> [DrawingActivity] {
        []
    }

    func recentActivities(limit: Int) async throws -> [DrawingActivity] {
        []
    }
}

public extension DependencyValues {
    var drawingActivityRepository: any DrawingActivityRepository {
        get { self[DrawingActivityRepositoryKey.self] }
        set { self[DrawingActivityRepositoryKey.self] = newValue }
    }
}
