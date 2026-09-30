//
//  CloudImportArrivalTesting.swift
//  DomainTest
//
//  import 성공 신호 — 열린 장이 늦게 도착한 필사를 반영하는 입구 (2026-09-21 후속 리뷰 P0-3).
//

@testable import Domain
import Foundation
import Testing

import Dependencies

/// 이 파일이 막는 것:
/// - 조회가 읽은 뒤 · 구독이 걸리기 전에 끝난 import 를 놓치는 것 — 구독 시점의 마지막 성공도 한 번 보낸다
/// - 진행 표시 · 내보내기처럼 import 성공이 아닌 활동 변화를 "도착" 으로 알리는 것
@Suite("늦게 도착한 필사 — import 성공 신호")
@MainActor
struct CloudImportArrivalTesting {
    @Test("구독 시점의 마지막 import 성공을 한 번 보내고, 그 뒤로는 새 성공만 보낸다")
    func arrivalsFollowImportSuccesses() async throws {
        let container = PersistentCloudKitContainer()
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)
        container.activity = CloudSyncActivity(lastImportSuccess: first)
        let stream = withDependencies {
            $0.clouodKitSyncManager = container
        } operation: {
            LiveCloudImportArrivalClient().arrivals()
        }
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == first)

        // import 성공이 아닌 변화 — 진행 중 · 내보내기 성공 — 는 알리지 않는다.
        container.activity = CloudSyncActivity(isRunning: true, lastImportSuccess: first)
        container.activity = CloudSyncActivity(lastImportSuccess: first, lastExportSuccess: second)
        container.activity = CloudSyncActivity(lastImportSuccess: second, lastExportSuccess: second)
        #expect(await iterator.next() == second)
    }

    @Test("아직 import 성공이 없으면 아무것도 보내지 않다가, 처음 성공하면 보낸다")
    func noArrivalBeforeTheFirstSuccess() async throws {
        let container = PersistentCloudKitContainer()
        let stream = withDependencies {
            $0.clouodKitSyncManager = container
        } operation: {
            LiveCloudImportArrivalClient().arrivals()
        }
        var iterator = stream.makeAsyncIterator()
        let success = Date(timeIntervalSince1970: 3_000)
        container.activity = CloudSyncActivity(isRunning: true)
        container.activity = CloudSyncActivity(lastImportSuccess: success)
        #expect(await iterator.next() == success)
    }
}
