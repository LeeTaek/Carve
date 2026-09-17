//
//  DrawingStoreGenerationTesting.swift
//  DomainTest
//
//  전체 삭제와 저장의 경쟁 (`DrawingStoreGeneration`).
//
//  삭제는 DB 를 지운 뒤에 열린 장에 알린다. 그 전에 요청된 저장이 actor 에서 삭제보다 **늦게** 실행되면
//  `create`(upsert) 와 `clear`(없으면 빈 행) 가 방금 지운 필사를 새 행으로 되살렸다. 순서를 테스트가 정해
//  "요청은 삭제 전, 실행은 삭제 뒤" 를 재현한다.
//

@testable import Domain
import Foundation
import SwiftData
import Testing

@Suite("전체 삭제 뒤 실행되는 저장")
struct DrawingStoreGenerationTesting {

    @Test("삭제 전에 조회한 세대의 create · clear 는 삭제 뒤에 실행되면 거절되고, 행을 만들지 않는다")
    func staleCreateAndClearWriteNothing() async throws {
        let harness = try RepositoryHarness()
        let eraser = SwiftDataDrawingDataEraser(actor: harness.actor)
        // 화면이 조회해 둔 세대. 이 조회를 기준으로 아래 명령들을 만들었다.
        let before = try await harness.repository.load(chapter: harness.chapter).generation

        #expect(await eraser.eraseAll() == .completed)

        // ★ 이전 구현: create 는 새 행을, clear 는 빈 행을 만들었다 — 방금 지운 절이 되살아난다.
        await #expect(throws: DrawingRepositoryError.staleStoreGeneration) {
            try await harness.repository.apply(
                [
                    .create(verse: 4, rowID: .issue(), data: Data([4]), metadata: harness.metadata(verse: 4)),
                    .clear(verse: 5, rowID: .issue())
                ],
                chapter: harness.chapter,
                generation: before
            )
        }

        // 다른 context 에서 읽는다 — 같은 context 는 저장하지 않은 변경도 보여 준다.
        let verifier = SwiftDatabaseActor(modelContainer: harness.actor.modelContainer)
        #expect(try await verifier.loadDrawingSnapshots(chapter: harness.chapter).isEmpty)
    }

    @Test("지워진 행을 가리키는 replace 도 rowNotFound 가 아니라 세대 거절로 온다 — 화면이 실패 안내 대신 삭제 뒤처리를 하도록")
    func staleReplaceIsReportedAsStaleGeneration() async throws {
        let harness = try RepositoryHarness()
        let eraser = SwiftDataDrawingDataEraser(actor: harness.actor)
        let existing = BibleDrawingRowID.issue()
        try await harness.apply(
            [.create(verse: 3, rowID: existing, data: Data([3]), metadata: harness.metadata(verse: 3))],
            chapter: harness.chapter
        )
        let before = try await harness.repository.load(chapter: harness.chapter).generation

        #expect(await eraser.eraseAll() == .completed)

        await #expect(throws: DrawingRepositoryError.staleStoreGeneration) {
            try await harness.repository.apply(
                [.replace(verse: 3, rowID: existing, data: Data([33]), metadata: harness.metadata(verse: 3))],
                chapter: harness.chapter,
                generation: before
            )
        }
    }

    @Test("삭제 뒤에 다시 조회한 세대로는 저장된다 — 지운 뒤 새로 쓴 필사는 막지 않는다")
    func freshGenerationIsAccepted() async throws {
        let harness = try RepositoryHarness()
        let eraser = SwiftDataDrawingDataEraser(actor: harness.actor)
        let before = try await harness.repository.load(chapter: harness.chapter).generation
        #expect(await eraser.eraseAll() == .completed)

        let after = try await harness.repository.load(chapter: harness.chapter).generation
        #expect(after != before)
        let rowID = BibleDrawingRowID.issue()
        try await harness.repository.apply(
            [.create(verse: 4, rowID: rowID, data: Data([4]), metadata: harness.metadata(verse: 4))],
            chapter: harness.chapter,
            generation: after
        )

        #expect(try await harness.load(chapter: harness.chapter).map(\.rowID) == [rowID])
    }

    @Test("삭제보다 먼저 실행된 저장은 삭제가 지운다 — 삭제는 세대와 무관하게 전부 지운다")
    func saveBeforeEraseIsErased() async throws {
        let harness = try RepositoryHarness()
        let eraser = SwiftDataDrawingDataEraser(actor: harness.actor)
        let generation = try await harness.repository.load(chapter: harness.chapter).generation
        try await harness.repository.apply(
            [.create(verse: 4, rowID: .issue(), data: Data([4]), metadata: harness.metadata(verse: 4))],
            chapter: harness.chapter,
            generation: generation
        )

        #expect(await eraser.eraseAll() == .completed)

        let verifier = SwiftDatabaseActor(modelContainer: harness.actor.modelContainer)
        #expect(try await verifier.loadDrawingSnapshots(chapter: harness.chapter).isEmpty)
    }

    @Test("삭제 전에 요청된 저장이 삭제와 어떤 순서로 실행돼도 남는 행이 없다")
    func anyInterleavingLeavesNothing() async throws {
        let harness = try RepositoryHarness()
        let eraser = SwiftDataDrawingDataEraser(actor: harness.actor)
        let generation = try await harness.repository.load(chapter: harness.chapter).generation
        let repository = harness.repository
        let chapter = harness.chapter
        let metadata = harness.metadata(verse: 1)

        // 삭제 앞뒤로 저장 요청을 흩어 놓는다. 앞선 것은 삭제가 지우고, 뒤선 것은 세대에 걸려야 한다.
        let outcome = await withTaskGroup(of: DrawingEraseOutcome?.self) { group in
            for index in 0..<40 {
                if index == 20 {
                    group.addTask { await eraser.eraseAll() }
                }
                group.addTask {
                    try? await repository.apply(
                        [.create(verse: index % 3 + 1, rowID: .issue(), data: Data([UInt8(index)]), metadata: metadata)],
                        chapter: chapter,
                        generation: generation
                    )
                    return nil
                }
            }
            var erased: DrawingEraseOutcome?
            for await result in group {
                if let result { erased = result }
            }
            return erased
        }

        #expect(outcome == .completed)
        let verifier = SwiftDatabaseActor(modelContainer: harness.actor.modelContainer)
        #expect(try await verifier.loadDrawingSnapshots(chapter: harness.chapter).isEmpty)
    }

    @Test("전체 삭제는 save 를 기다리지 않고 저장소에 반영된다 — 세대를 곧바로 올려도 되는 근거")
    func eraseReachesStoreWithoutSave() async throws {
        let harness = try RepositoryHarness()
        try await harness.apply(
            [.create(verse: 4, rowID: .issue(), data: Data([1]), metadata: harness.metadata(verse: 4))],
            chapter: harness.chapter
        )
        let verifier = SwiftDatabaseActor(modelContainer: harness.actor.modelContainer)
        #expect(try await verifier.loadDrawingSnapshots(chapter: harness.chapter).count == 1)

        #expect(await SwiftDataDrawingDataEraser(actor: harness.actor).eraseAll() == .completed)

        #expect(try await verifier.loadDrawingSnapshots(chapter: harness.chapter).isEmpty)
    }
}
