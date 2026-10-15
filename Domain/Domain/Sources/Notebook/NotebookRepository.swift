//
//  NotebookRepository.swift
//  Domain
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

/// 필사책 목록 · 메타데이터의 접근 경로. Feature 는 이 계약만 알고 SwiftData 모델(`DrawingNotebook` · `BibleDrawing`)을 만지지 않는다.
///
/// - 기본 필사책의 메타데이터 레코드는 이름을 바꾸거나 완료를 표시할 때만 `notebookID == "default"` 로 생긴다.
/// - 같은 `notebookID` 의 레코드가 둘 이상이면(두 기기가 따로 만듦) `updatedAt` 최신을 쓴다 — unique 제약이 없다(CloudKit 미러링).
/// - 지금 필사책(기기마다)은 이 저장소가 아니라 `@Shared(.currentNotebookID)` 다.
public protocol NotebookRepository: Sendable {
    /// 모든 필사책 — 기본이 늘 첫째, 나머지는 `createdAt` 오름차순이고 `createdAt` 이 nil 인 것은 뒤다.
    ///
    /// 메타데이터가 없어도 행이 있는 필사책은 든다(`hasMetadata == false`). 기본 필사책은 행 · 메타데이터가 없어도 든다.
    func notebooks() async throws -> [NotebookSnapshot]

    /// 새 필사책의 메타데이터를 만든다. `id` 는 호출부가 `NotebookID.make(uuid:)` 로 짓는다.
    /// - Parameters:
    ///   - id: 새 필사책 ID.
    ///   - name: 이름(사용자 입력 — 옮기지 않는다).
    ///   - now: 만든 시각(`createdAt` · `updatedAt`). 호출부가 `@Dependency(\.date)` 로 넘긴다.
    func create(id: NotebookID, name: String, now: Date) async throws

    /// 이름을 바꾼다. 기본 필사책도 바꿀 수 있다 — 메타데이터가 없으면 만든다.
    func rename(_ id: NotebookID, to name: String, now: Date) async throws

    /// 완료를 표시하거나 취소한다. 표시일 뿐 쓰기를 막지 않는다. 메타데이터가 없으면 만든다.
    func setCompleted(_ id: NotebookID, _ completed: Bool, now: Date) async throws

    /// 필사책과 그 필사책의 필기 전부를 지운다. 기본 필사책이면 `NotebookRepositoryError.cannotDeleteDefault` 를 던지고 아무것도 지우지 않는다.
    func delete(_ id: NotebookID) async throws
}

private enum NotebookRepositoryKey: DependencyKey {
    /// 실제 SwiftData 구현은 아직 없다(t1b 가 바꾼다). 주입하지 않고 부르면 문제로 알린다.
    static let liveValue: any NotebookRepository = UnimplementedNotebookRepository()
    /// 테스트 기본값은 **아무 저장소도 건드리지 않는다** — 공유 SwiftData actor 를 깨우지 않는다(룰북 testing.md).
    /// 필사책을 확인하는 시험은 자기 대역이나 인메모리 저장소를 주입한다.
    static let testValue: any NotebookRepository = EmptyNotebookRepository()
    static let previewValue: any NotebookRepository = EmptyNotebookRepository()
}

public extension DependencyValues {
    /// 필사책 저장소.
    var notebookRepository: any NotebookRepository {
        get { self[NotebookRepositoryKey.self] }
        set { self[NotebookRepositoryKey.self] = newValue }
    }
}

/// 메타데이터 없는 기본 필사책 하나 — 빈 저장소가 돌려주는 목록.
private let defaultNotebookOnly = NotebookSnapshot(
    id: .default,
    name: nil,
    status: .active,
    createdAt: nil,
    completedAt: nil,
    writtenVerseCount: 0,
    hasMetadata: false
)

/// 비어 있는 필사책 저장소 — 목록은 기본 필사책 하나, 쓰기는 버린다. 테스트 · 미리보기 기본값이다.
private struct EmptyNotebookRepository: NotebookRepository {
    func notebooks() async throws -> [NotebookSnapshot] {
        [defaultNotebookOnly]
    }

    func create(id: NotebookID, name: String, now: Date) async throws {}

    func rename(_ id: NotebookID, to name: String, now: Date) async throws {}

    func setCompleted(_ id: NotebookID, _ completed: Bool, now: Date) async throws {}

    func delete(_ id: NotebookID) async throws {}
}

/// 주입하지 않았을 때 — 저장한 척하지 않고 문제로 알린다. 목록은 기본 필사책 하나로 돌려 화면이 비지 않게 한다.
private struct UnimplementedNotebookRepository: NotebookRepository {
    func notebooks() async throws -> [NotebookSnapshot] {
        reportIssue("NotebookRepository 를 주입하지 않았다 — notebooks()")
        return [defaultNotebookOnly]
    }

    func create(id: NotebookID, name: String, now: Date) async throws {
        reportIssue("NotebookRepository 를 주입하지 않았다 — create(id:name:now:)")
    }

    func rename(_ id: NotebookID, to name: String, now: Date) async throws {
        reportIssue("NotebookRepository 를 주입하지 않았다 — rename(_:to:now:)")
    }

    func setCompleted(_ id: NotebookID, _ completed: Bool, now: Date) async throws {
        reportIssue("NotebookRepository 를 주입하지 않았다 — setCompleted(_:_:now:)")
    }

    func delete(_ id: NotebookID) async throws {
        reportIssue("NotebookRepository 를 주입하지 않았다 — delete(_:)")
    }
}
