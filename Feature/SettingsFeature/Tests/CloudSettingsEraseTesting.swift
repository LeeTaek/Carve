//
//  CloudSettingsEraseTesting.swift
//  SettingsFeatureTest
//
//  설정 → 「모든 필사 데이터 삭제」 가 실패했을 때 (로드맵 SAVE-2).
//

import Domain
import Foundation
import Testing

import ComposableArchitecture

@testable import SettingsFeature

/// 정해 둔 결과를 차례로 돌려주는 삭제 스텁.
private final class EraserStub: DrawingDataEraser, @unchecked Sendable {
    let outcomes: LockIsolated<[DrawingEraseOutcome]>
    let calls = LockIsolated(0)

    init(_ outcomes: [DrawingEraseOutcome]) {
        self.outcomes = LockIsolated(outcomes)
    }

    func eraseAll() async -> DrawingEraseOutcome {
        calls.withValue { $0 += 1 }
        return outcomes.withValue { $0.isEmpty ? .completed : $0.removeFirst() }
    }
}

/// 위젯을 비운 횟수를 세고, 정해 둔 횟수만큼 실패한다.
///
/// 이전 스파이는 항상 성공해서 "위젯 삭제가 실패해도 완료를 띄우는" 결함을 잡지 못했다.
private final class WidgetClearSpy: WidgetVerseClient, @unchecked Sendable {
    struct ClearFailed: Error {}
    let clearCount = LockIsolated(0)
    /// 앞에서부터 이만큼 실패한다.
    let failuresRemaining: LockIsolated<Int>

    init(failing failures: Int = 0) {
        failuresRemaining = LockIsolated(failures)
    }

    func selection() async -> [FavoriteVerseKey] { [] }
    func select(_ favorites: [FavoriteVerseSnapshot]) async throws {}
    func add(_ favorite: FavoriteVerseSnapshot) async throws {}
    func remove(_ key: FavoriteVerseKey) async throws {}
    func clear() async throws {
        clearCount.withValue { $0 += 1 }
        let shouldFail = failuresRemaining.withValue { remaining -> Bool in
            guard remaining > 0 else { return false }
            remaining -= 1
            return true
        }
        if shouldFail { throw ClearFailed() }
    }
}

/// 전체 삭제 확인 문구 — **남은 필기(보존 영역)도 함께 지워진다**(ACC-1 2차 ㉓).
///
/// 저장소가 비어도 초안만 남아 있을 수 있는데, 이전 문구는 그것을 말하지 않았고 "지울 필사 데이터가 없어요" 로 닫혔다.
@Suite("설정 — 전체 삭제 문구")
struct CloudSettingsEraseCopyTesting {

    @Test("남은 초안이 있으면 문구가 그 수까지 말한다 — 자동으로 표시되는 것 · 다른 계정 · 읽지 못한 파일까지 모두라는 것도")
    func bodyMentionsRemainingDrafts() {
        let body = CloudSettingsFeature.eraseConfirmBody(remainingDrafts: 13)
        #expect(body.contains("이 기기의 필사 초안 13개도 모두 지워져요"))
        #expect(body.contains("다른 계정에서 쓴 것 · 읽지 못한 파일 포함"))
        // 센 것은 "보이지 않는 것" 만이 아니다 — 그렇게 말하지 않는다(P1-4).
        #expect(!body.contains("보이지 않"))
    }

    @Test("남은 초안을 세지 못했으면 수 없이 말하되 빼지 않는다")
    func bodyMentionsDraftsWithoutCountWhenUnknown() {
        let body = CloudSettingsFeature.eraseConfirmBody(remainingDrafts: nil)
        #expect(body.contains("이 기기의 필사 초안도 모두 지워져요"))
    }

    @Test("남은 초안이 없으면 그 줄을 넣지 않는다")
    func bodyOmitsDraftLineWhenNone() {
        let body = CloudSettingsFeature.eraseConfirmBody(remainingDrafts: 0)
        #expect(!body.contains("초안"))
        #expect(body.contains("모든 장의 필기와 이전 필사 기록이 지워져요"))
    }

    /// 2026-09-21 후속 리뷰 P1-4 — 문구의 수와 실제로 지워지는 대상이 같아야 한다. 실제 보존 영역에 여러 묶음의 초안과 읽지 못한 파일을 두고
    /// 전체 삭제를 돌려, 센 수만큼 파일이 사라지는지 본다.
    @Test("문구의 수는 전체 삭제가 실제로 지우는 초안 파일 수다 — 다른 계정 묶음 · 읽지 못한 파일까지")
    func countMatchesWhatEraseRemoves() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("erase-count-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let area = PreservationArea(root: root.appendingPathComponent("Preservation", isDirectory: true), storeFileName: "Carve.sqlite")
        let writer = LocalPreservationWriter(
            area: area, eraseState: EraseStateArea(root: root.appendingPathComponent("EraseState", isDirectory: true), storeFileName: "Carve.sqlite")
        )
        let chapter = BibleChapter(title: .genesis, chapter: 1)
        func draft(_ verse: Int, _ scope: AccountScope, revision: Int = 1) -> VerseDraft {
            VerseDraft(
                key: VerseDraftKey(sessionID: "s-\(scope.key)", chapter: chapter, verse: verse), revision: revision,
                rowID: BibleDrawingRowID(raw: "row-\(verse)"), lineData: Data("획".utf8), drawingVersion: 3, layoutMetadataData: nil,
                base: .empty, baseFingerprint: nil, account: .confirmed(AccountServerWorkToken(scope: scope, generation: 1)),
                knownEpochs: [], storeOwnership: nil, eraseGeneration: 0, savedAt: Date(timeIntervalSince1970: 1_000)
            )
        }
        let accountA = AccountScope(key: "acct-a")
        let accountB = AccountScope(key: "acct-b")
        _ = try await writer.saveDraft(draft(1, accountA))
        _ = try await writer.saveDraft(draft(2, accountA))
        _ = try await writer.saveDraft(draft(3, accountB))
        // 같은 키의 초안을 읽지 못하게 만들고 다시 쓰면 옛 파일이 옆으로 옮겨진다 — 읽지 못한 파일 하나.
        let files = { (try? FileManager.default.subpathsOfDirectory(atPath: area.draftsDirectory.path)) ?? [] }
        let draftTwo = try #require(files().first { $0.hasPrefix(accountA.key) && $0.hasSuffix("~2.json") })
        try Data("{ 잘린".utf8).write(to: area.draftsDirectory.appendingPathComponent(draftTwo))
        _ = try await writer.saveDraft(draft(2, accountA, revision: 2))

        let counted = try #require(await CloudSettingsFeature.remainingDraftCount(writer))
        let draftFiles = files().filter { $0.hasSuffix(".json") || $0.contains(".unreadable-") }
        #expect(counted == 4)
        #expect(counted == draftFiles.count)
        #expect(CloudSettingsFeature.eraseConfirmBody(remainingDrafts: counted).contains("필사 초안 \(counted)개"))

        try await writer.eraseAllLocal()
        #expect(files().isEmpty)
    }

    @Test("보존 영역을 열지 못하면 남은 필기 수는 nil 이다 — 0 이 아니다")
    func remainingCountIsNilWithoutReader() async {
        #expect(await CloudSettingsFeature.remainingDraftCount(nil) == nil)
    }
}

/// 이전 구현은 삭제 중 하나라도 throw 하면
/// ① 로딩 해제에 도달하지 못해 **화면 전체가 잠겼고**
/// ② 필사 행은 지워졌는데 열린 장에 알리지 않아 **다음 저장이 지운 필사를 되살렸고**
/// ③ 「다시 시도」 의 확인이 필사 행만 다시 봐서 **남은 즐겨찾기를 지우지 않고 닫혔다.**
@Suite("설정 — 전체 삭제 실패")
@MainActor
struct CloudSettingsEraseTesting {
    private func makeStore(
        _ eraser: EraserStub,
        widget: WidgetClearSpy,
        initialState: CloudSettingsFeature.State = .initialState
    ) -> TestStoreOf<CloudSettingsFeature> {
        TestStore(initialState: initialState) {
            CloudSettingsFeature()
        } withDependencies: {
            $0.drawingDataEraser = eraser
            $0.widgetVerseClient = widget
        }
    }

    private func retryPopup(body: String) -> CloudSettingsFeature.Path.State {
        .popup(.init(
            title: "필사 데이터를 모두 지우지 못했어요",
            body: body,
            confirmTitle: "다시 시도",
            cancelTitle: "닫기",
            role: .destructive,
            confirmAction: .deleteAllData
        ))
    }

    @Test("필사 행 삭제가 실패하면 열린 장에 알리지 않고, 지웠다고도 지우지 않았다고도 단정하지 않는다. 잠금은 풀고 다시 시도를 둔다")
    func nothingErasedKeepsPendingAndUnlocks() async {
        let eraser = EraserStub([.failed])
        let widget = WidgetClearSpy()
        let store = makeStore(eraser, widget: widget)

        await store.send(.removeAlliCloudData)
        await store.receive(\.setLoading) { $0.isLoading = true }
        // ★ `drawingDataCleared` 가 끼어들면 이 순서가 어긋나 실패한다.
        await store.receive(\.setLoading) { $0.isLoading = false }
        await store.receive(\.presentPopover) {
            // 일부가 지워졌는지 증명하지 못하므로 "아무것도 지우지 않았다" 고 단정하지 않는다.
            $0.path = self.retryPopup(body: "삭제를 완료하지 못했어요. 다시 시도해 주세요.")
        }

        // 필사 행을 지웠다고 확인하지 못했으므로 위젯의 말씀도 그대로 둔다 — 미저장분을 지키는 것과 같은 판단이다.
        #expect(widget.clearCount.value == 0)
    }

    @Test("필사 행만 지우고 실패하면 열린 장에 알리고 위젯도 비운다 — 그러지 않으면 지운 필사가 되살아난다")
    func partialEraseNotifiesOpenChapter() async {
        let eraser = EraserStub([.partiallyFailed])
        let widget = WidgetClearSpy()
        let store = makeStore(eraser, widget: widget)

        await store.send(.removeAlliCloudData)
        await store.receive(\.setLoading) { $0.isLoading = true }
        await store.receive(\.drawingDataCleared)
        await store.receive(\.setLoading) { $0.isLoading = false }
        await store.receive(\.presentPopover) {
            $0.path = self.retryPopup(body: "필기는 지웠지만 즐겨찾기가 남았을 수 있어요.")
        }

        #expect(widget.clearCount.value == 1)
    }

    @Test("전부 지우면 열린 장에 알리고 완료를 알린다")
    func completeEraseNotifiesAndConfirms() async {
        let eraser = EraserStub([.completed])
        let widget = WidgetClearSpy()
        let store = makeStore(eraser, widget: widget)

        await store.send(.removeAlliCloudData)
        await store.receive(\.setLoading) { $0.isLoading = true }
        await store.receive(\.drawingDataCleared)
        await store.receive(\.setLoading) { $0.isLoading = false }
        await store.receive(\.presentPopover) {
            $0.path = .popup(.init(body: "모든 필사 데이터를 지웠어요.", confirmTitle: "확인", confirmAction: .dismiss))
        }

        #expect(widget.clearCount.value == 1)
    }

    @Test("삭제 확인은 필사 행을 다시 보지 않고 곧바로 지운다 — 즐겨찾기만 남은 경우도 지워진다")
    func confirmErasesWithoutRecheckingDrawings() async {
        let eraser = EraserStub([.completed])
        var state = CloudSettingsFeature.State.initialState
        state.path = retryPopup(body: "필기는 지웠지만 즐겨찾기가 남았을 수 있어요.")
        let store = makeStore(eraser, widget: WidgetClearSpy(), initialState: state)
        store.exhaustivity = .off

        await store.send(.path(.presented(.popup(.view(.confirm)))))
        await store.receive(\.removeAlliCloudData)
        await store.receive(\.presentPopover)

        #expect(eraser.calls.value == 1)
    }

    @Test("부분 실패 뒤 「다시 시도」 는 같은 삭제를 다시 불러 남은 것을 지운다")
    func retryAfterPartialFailureErasesTheRest() async {
        let eraser = EraserStub([.partiallyFailed, .completed])
        let store = makeStore(eraser, widget: WidgetClearSpy())
        store.exhaustivity = .off

        await store.send(.removeAlliCloudData)
        await store.receive(\.presentPopover)
        #expect(store.state.path?.popup?.confirmAction == .deleteAllData)
        #expect(!store.state.isLoading)

        await store.send(.path(.presented(.popup(.view(.confirm)))))
        await store.receive(\.removeAlliCloudData)
        await store.receive(\.presentPopover)

        #expect(eraser.calls.value == 2)
        #expect(store.state.path?.popup?.body == "모든 필사 데이터를 지웠어요.")
        #expect(!store.state.isLoading)
    }

    // MARK: 위젯 삭제 실패

    @Test("DB 는 전부 지웠어도 위젯을 못 비우면 완료가 아니다 — 알리고 다시 시도를 둔다")
    func widgetClearFailureIsNotCompletion() async {
        let eraser = EraserStub([.completed])
        let widget = WidgetClearSpy(failing: 1)
        let store = makeStore(eraser, widget: widget)

        await store.send(.removeAlliCloudData)
        await store.receive(\.setLoading) { $0.isLoading = true }
        // 필사 행은 지워졌으므로 열린 장에는 알린다.
        await store.receive(\.drawingDataCleared)
        await store.receive(\.setLoading) { $0.isLoading = false }
        await store.receive(\.presentPopover) {
            $0.path = self.retryPopup(body: "필기와 즐겨찾기는 지웠지만 위젯에 담은 말씀이 남았을 수 있어요.")
        }
        #expect(widget.clearCount.value == 1)
    }

    @Test("필사 행만 지우고 위젯도 못 비우면 남은 것을 둘 다 말한다")
    func partialEraseAndWidgetFailureNamesBoth() async {
        let eraser = EraserStub([.partiallyFailed])
        let store = makeStore(eraser, widget: WidgetClearSpy(failing: 1))
        store.exhaustivity = .off

        await store.send(.removeAlliCloudData)
        await store.receive(\.presentPopover)

        #expect(store.state.path?.popup?.body == "필기는 지웠지만 즐겨찾기와 위젯에 담은 말씀이 남았을 수 있어요.")
        #expect(store.state.path?.popup?.confirmAction == .deleteAllData)
    }

    @Test("위젯 삭제 실패 뒤 「다시 시도」 가 성공하면 완료를 알린다")
    func retryAfterWidgetFailureCompletes() async {
        let eraser = EraserStub([.completed, .completed])
        let widget = WidgetClearSpy(failing: 1)
        let store = makeStore(eraser, widget: widget)
        store.exhaustivity = .off

        await store.send(.removeAlliCloudData)
        await store.receive(\.presentPopover)
        #expect(store.state.path?.popup?.confirmAction == .deleteAllData)

        await store.send(.path(.presented(.popup(.view(.confirm)))))
        await store.receive(\.removeAlliCloudData)
        await store.receive(\.presentPopover)

        #expect(widget.clearCount.value == 2)
        #expect(store.state.path?.popup?.body == "모든 필사 데이터를 지웠어요.")
    }
}
