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
