//
//  ChapterCanvasDraftFileTesting.swift
//  CarveFeatureTest
//
//  편집 화면과 **실제 초안 파일** — 깨진 파일은 그 장을 막고, 되돌리면 다시 열린다 (정책 §12-6 구현 순서 ②, 10차 리뷰 1).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import CarveFeature

/// 이 파일이 막는 것:
/// - 대역이 아니라 **실제 저장소**(`LocalPreservationWriter`)를 썼을 때 읽기 실패가 삼켜져, 보이지 않는 초안 위에 새 초안이 덮이는 것
/// - 깨진 파일을 되돌려도 그 장이 계속 막혀 있는 것
@Suite("절 초안 — 실제 파일")
@MainActor
struct ChapterCanvasDraftFileTesting: DraftTestSamples {

    private struct Area {
        let root: URL
        let writer: LocalPreservationWriter
        let drafts: URL
    }

    private func makeArea() -> Area {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-draft-\(UUID().uuidString)", isDirectory: true)
        let preservation = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
        let eraseState = EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        return Area(
            root: root,
            writer: LocalPreservationWriter(area: preservation, eraseState: eraseState),
            drafts: preservation.draftsDirectory
        )
    }

    /// 지금 남아 있는 초안 파일들.
    private func draftFiles(_ area: Area) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: area.drafts, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    }

    @Test("이 기기의 초안 파일이 깨지면 그 장을 막고 덮지 않으며, 파일을 되돌리면 다시 시도로 열린다")
    func corruptDraftFileBlocksChapterUntilFixed() async throws {
        let area = makeArea()
        defer { try? FileManager.default.removeItem(at: area.root) }
        let spy = RepositorySpy()
        // 소유 근거가 없는 세션 — 이 필기의 사본은 초안 파일 하나뿐이다.
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: area.writer)
        await composeAndSubscribe(store, environment)
        await draw(store)
        await store.receive(\.draftsSaved)

        let files = draftFiles(area)
        #expect(files.count == 1)
        let url = try #require(files.first)
        let original = try Data(contentsOf: url)
        try Data("깨진 초안".utf8).write(to: url)

        // 같은 장을 다시 읽는다(레이아웃 변경) — 초안을 읽지 못해 막힌다.
        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout))
        await store.receive(\.drawingsLoaded)

        let failure = try #require(store.state.blockingLoadFailure)
        #expect(failure.source == .drafts)
        #expect(!store.state.isInputEnabled)
        #expect(LoadFailureNoticeView.message(for: failure) == LoadFailureNoticeView.draftsMessage)

        // 막힌 동안 같은 키 · 더 새 revision 으로 덮지 않았다.
        #expect(draftFiles(area).count == 1)
        #expect(try Data(contentsOf: url) == Data("깨진 초안".utf8))

        try original.write(to: url)
        await store.send(.retryLoad)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.isInputEnabled)
        #expect(store.state.blockingLoadFailure == nil)
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 && $0.lineData == Data("create-a".utf8) } == true)
        await end(store, environment)
    }

    /// 2026-09-21 후속 리뷰 P0-2a — 캔버스는 읽는 묶음을 합쳐 한 번 판정하는데 목록은 묶음마다 돌아, 캔버스에서 밀린 초안이 목록에도 없었다.
    @Test("같은 절 · 같은 기준의 초안이 계정 묶음과 확인 전(힌트 A) 묶음에 하나씩이면, 캔버스가 감춘 초안이 「남은 필기」 목록에 그대로 오른다")
    func canvasHiddenDraftIsListedInRecovery() async throws {
        let area = makeArea()
        defer { try? FileManager.default.removeItem(at: area.root) }
        let spy = spyWithVerseOne()
        var newer = previousDraft(session: "account-session", ink: "account-ink")
        newer.savedAt = Date(timeIntervalSince1970: 900)
        var older = previousDraft(session: "unverified-session", ink: "unverified-ink", account: .unverified(hint: accountA))
        older.savedAt = Date(timeIntervalSince1970: 800)
        _ = try await area.writer.saveDraft(newer)
        _ = try await area.writer.saveDraft(older)
        let current = confirmed(accountA, 1, owned: false)
        let environment = ControlledEditEnvironment(current)
        let store = makeStore(spy: spy, results: [], environment: environment, drafts: area.writer)
        await composeAndSubscribe(store, environment)

        // 캔버스 — 늦게 쓴 계정 묶음의 초안을 보이고, 확인 전 묶음의 초안은 감춘다(절 메뉴의 「남은 필기 1」).
        #expect(store.state.loadedDrawings?.first { $0.verse == 1 }?.lineData == Data("account-ink".utf8))
        #expect(store.state.drafts.hiddenCounts == [1: 1])

        // 목록 — 같은 파일 · 같은 저장소로 묶음마다 조회한다. 감춘 그 초안이 자기 묶음에 한 번 오른다.
        let query = VerseDraftRecoveryQuery(reader: area.writer, repository: spy)
        let listed = try await query.inventory(in: accountA, environment: current).entries
            + query.inventory(in: .unverified, environment: current).entries
        #expect(listed.map(\.draft) == [older])
        #expect(listed.map(\.reason) == [.newerDraftShown])
        await end(store, environment)
    }

    @Test("초안 폴더를 읽지 못하는 동안에도 막고, 권한이 돌아오면 그 초안을 그대로 보인다")
    func unreadableDraftFolderBlocksChapter() async throws {
        let area = makeArea()
        defer { try? FileManager.default.removeItem(at: area.root) }
        let spy = RepositorySpy()
        let environment = ControlledEditEnvironment(confirmed(accountA, 1, owned: false))
        let store = makeStore(spy: spy, results: [CanvasTestSupport.createResult("a")], environment: environment, drafts: area.writer)
        await composeAndSubscribe(store, environment)
        await draw(store)
        await store.receive(\.draftsSaved)

        let bucket = try #require(draftFiles(area).first).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: bucket.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bucket.path) }

        await store.send(.layoutCompleted(CanvasTestSupport.otherLayout))
        await store.receive(\.drawingsLoaded)
        #expect(store.state.blockingLoadFailure?.source == .drafts)
        #expect(!store.state.isInputEnabled)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bucket.path)
        await store.send(.retryLoad)
        await store.receive(\.drawingsLoaded)

        #expect(store.state.isInputEnabled)
        #expect(store.state.loadedDrawings?.contains { $0.verse == 2 && $0.lineData == Data("create-a".utf8) } == true)
        await end(store, environment)
    }
}
