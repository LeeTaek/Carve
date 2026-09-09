//
//  DrawingRepository.swift
//  Domain
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation

import Dependencies

/// 단일 Canvas 의 SwiftData 단일 접근 경로 (설계 §4 · §8-6).
///
/// Feature 는 이 계약만 알고 SwiftData 모델(`BibleDrawing`)을 직접 만지지 않는다.
/// `apply` 는 **전부 성공 또는 전부 실패**다 (P8).
///
/// > 한계 — 로컬 원자성 ≠ CloudKit 원자성 (§8-6). 로컬 트랜잭션이 절 3개를 한 번에 커밋해도 CloudKit 에는
/// > CKRecord 3개로 개별 동기화된다. 다른 기기가 일시적으로 찢어진 상태를 볼 수 있다.
public protocol DrawingRepository: Sendable {
    /// 장의 **모든 행**을 읽는다 (히스토리 행 포함). 대표 행 선택은 호출부가 `representativesByVerse()` 로 한다.
    /// - Parameter chapter: 대상 장.
    /// - Returns: 절 → 행 키 순으로 정렬된 스냅샷.
    func load(chapter: BibleChapter) async throws -> [VerseDrawingSnapshot]

    /// 한 편집의 모든 절 저장을 단일 트랜잭션으로 적용한다.
    /// - Parameters:
    ///   - mutations: 절별 저장 명령. 같은 rowID 가 둘 이상 있으면 안 된다 (coalescing 은 호출부 책임, §8-3).
    ///   - chapter: 대상 장. `create` 가 행을 만들 때의 권·장이다.
    func apply(_ mutations: [VerseDrawingMutation], chapter: BibleChapter) async throws

    /// 절의 현재 필사를 **보관 행**으로 남기고 활성 행을 빈 상태로 되돌린다 — 한 트랜잭션 (UI-2 "지우기").
    ///
    /// `apply` 와 **별도의 작업**이다. 저장 큐(§8-3)는 rowID 당 한 칸이라 나중 명령이 앞 명령을 대체하므로,
    /// 보관 명령을 그 큐에 넣으면 이어진 획 하나에 덮여 사라진다. 호출부는 이 작업을 일반 획 저장과
    /// **순서가 보장되도록** 다뤄야 한다 — flush 로 큐를 비운 뒤에 부르고, 도는 동안 새 저장을 시작하지 않는다.
    ///
    /// | 하는 일 | 내용 |
    /// |---|---|
    /// | 보관 행 | `archiveRowID` 로 upsert. 활성 행의 `lineData` · metadata · `drawingVersion` 을 복제하고 **`isPresent = false`** |
    /// | 활성 행 | 행을 유지한 채 `lineData = nil`, **`isPresent = true`** (대표 유지), `updateDate` 갱신 |
    /// | 아무것도 안 함 | 활성 행이 없거나 이미 획이 없으면 `alreadyEmpty` — 쓰기 0건 |
    ///
    /// - Important: **호출 전에 미저장분이 전부 저장돼 있어야 한다.** 이 메서드는 DB 의 활성 행 내용을 보관하므로,
    ///              진행 중 편집·대기 저장이 남아 있으면 "방금까지 쓴 내용" 이 아니라 그 이전 내용을 보관한다 (§8-5 flush).
    ///              `alreadyEmpty` 판정도 같은 이유로 flush 이후여야 한다 — DB 는 비었는데 미저장 획이 화면에 있을 수 있다.
    /// - Note: 대표 규칙(`DrawingRepresentativeRule`)은 `isPresent` 를 먼저 보므로 보관 행은 다시 대표로 뽑히지 않는다.
    ///         `VerseDrawingMutation.clear` 는 `isPresent` 를 건드리지 않으므로 이 보장을 대신하지 못한다.
    ///
    /// > 한계 — 로컬 원자성 ≠ CloudKit 원자성 (§8-6). 보관 행과 비워진 활성 행은 CKRecord 2개로 각각 동기화되므로
    /// > 다른 기기가 둘 중 하나만 먼저 볼 수 있다.
    /// - Parameters:
    ///   - command: 대상 절·활성 행·보관 행 식별자. `archiveRowID` 는 **재시도에도 같은 값**이어야 한다.
    ///   - chapter: 대상 장.
    /// - Returns: 실제로 보관했는지 여부.
    func archiveAndReset(
        _ command: VerseDrawingArchiveCommand,
        chapter: BibleChapter
    ) async throws -> VerseDrawingArchiveOutcome
}

private enum DrawingRepositoryKey: DependencyKey {
    static let liveValue: any DrawingRepository = SwiftDataDrawingRepository()
    static var testValue: any DrawingRepository {
        withDependencies {
            $0.createSwiftDataActor = .testValue
        } operation: {
            SwiftDataDrawingRepository()
        }
    }
    static var previewValue: any DrawingRepository {
        withDependencies {
            $0.createSwiftDataActor = .previewValue
        } operation: {
            SwiftDataDrawingRepository()
        }
    }
}

public extension DependencyValues {
    var drawingRepository: any DrawingRepository {
        get { self[DrawingRepositoryKey.self] }
        set { self[DrawingRepositoryKey.self] = newValue }
    }
}
