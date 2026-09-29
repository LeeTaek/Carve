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
public struct DrawingActivity: Equatable, Sendable {
    /// 마지막으로 고친 시각.
    public let updateDate: Date?
    /// 권 이름(`BibleTitle.rawValue`).
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
