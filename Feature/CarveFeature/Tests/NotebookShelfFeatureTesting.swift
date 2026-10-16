//
//  NotebookShelfFeatureTesting.swift
//  CarveFeatureTest
//
//  2.2 「회차별 필사책」 — 책장(설계 §6-1 ~ §6-7): 목록 · 만들기 · 이름 · 완료 표시 · 지우기 순서 · 저장소 쓰기 막음 · 이름 제안 · 카드 문구.
//  시각 `@Dependency(\.date)` · 새 ID `@Dependency(\.uuid)` 를 고정한다. 대역은 `let` · `LockIsolated` 로 둔다(룰북 testing.md).
//

@testable import CarveFeature
import ClientInterfaces
import Domain
import Foundation
import Testing

import ComposableArchitecture

// MARK: - 준비물

/// 책장 시험의 필사책 · 시각.
enum ShelfFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let newUUID = UUID(uuidString: "0F3A1C2D-0000-4000-8000-0000000000C1")!
    static let second = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-0000000000B2")!)
    /// 세 번째 필사책 — 정보 없이 행만 있다(이름 없는 필사책).
    static let third = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-0000000000B3")!)

    /// 기본 필사책 — 이름을 바꾼 적이 없어 정보가 없다.
    static let defaultNotebook = NotebookSnapshot(
        id: .default, name: nil, status: .active, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        completedAt: nil, writtenVerseCount: 120, hasMetadata: false
    )
    static let secondNotebook = NotebookSnapshot(
        id: second, name: "두 번째 필사", status: .active, createdAt: Date(timeIntervalSince1970: 1_760_000_000),
        completedAt: nil, writtenVerseCount: 12, hasMetadata: true
    )
    static let thirdNotebook = NotebookSnapshot(
        id: third, name: nil, status: .active, createdAt: nil, completedAt: nil, writtenVerseCount: 3, hasMetadata: false
    )
}

/// 필사책 저장소 대역 — 목록을 정해 두고, 쓰기 호출을 순서대로 남기며 목록에도 반영한다.
final class ShelfRepositorySpy: NotebookRepository {
    enum Call: Equatable, Sendable {
        case create(NotebookID, name: String, now: Date)
        case rename(NotebookID, name: String, now: Date)
        case setCompleted(NotebookID, Bool, now: Date)
        case delete(NotebookID)
    }

    struct Failure: Error {}

    let listed: LockIsolated<[NotebookSnapshot]>
    let reads = LockIsolated(0)
    let calls = LockIsolated<[Call]>([])
    /// 지우기 · 초안 버리기 · 위임이 일어난 순서 — 함께 쓰는 대역 · 부모가 같은 기록에 남긴다.
    let events: LockIsolated<[String]>
    /// 지울 때 본 지금 필사책 키 — 키를 먼저 기본으로 돌렸는지 본다.
    let keyAtDelete = LockIsolated<String?>(nil)
    /// 지금 필사책 키를 읽을 UserDefaults 묶음 이름(UserDefaults 는 Sendable 이 아니라 이름만 든다).
    let suiteName: String?
    /// 목록 읽기 · 쓰기를 실패시킨다.
    let failsReads = LockIsolated(false)
    let failsWrites = LockIsolated(false)

    init(_ notebooks: [NotebookSnapshot], events: LockIsolated<[String]> = LockIsolated([]), suiteName: String? = nil) {
        self.listed = LockIsolated(notebooks)
        self.events = events
        self.suiteName = suiteName
    }

    func notebooks() async throws -> [NotebookSnapshot] {
        reads.withValue { $0 += 1 }
        if failsReads.value { throw Failure() }
        return listed.value
    }

    func create(id: NotebookID, name: String, now: Date) async throws {
        try record(.create(id, name: name, now: now))
        listed.withValue {
            $0.append(NotebookSnapshot(id: id, name: name, status: .active, createdAt: now, completedAt: nil, writtenVerseCount: 0, hasMetadata: true))
        }
    }

    func rename(_ id: NotebookID, to name: String, now: Date) async throws {
        try record(.rename(id, name: name, now: now))
        update(id) { $0.name = name }
    }

    func setCompleted(_ id: NotebookID, _ completed: Bool, now: Date) async throws {
        try record(.setCompleted(id, completed, now: now))
        update(id) {
            $0.status = completed ? .completed : .active
            $0.completedAt = completed ? now : nil
        }
    }

    func delete(_ id: NotebookID) async throws {
        if let suiteName {
            keyAtDelete.setValue(UserDefaults(suiteName: suiteName)?.string(forKey: "currentNotebookID"))
        }
        events.withValue { $0.append("delete(\(id.rawValue))") }
        try record(.delete(id))
        listed.withValue { $0.removeAll { $0.id == id } }
    }

    private func record(_ call: Call) throws {
        calls.withValue { $0.append(call) }
        if failsWrites.value { throw Failure() }
    }

    private func update(_ id: NotebookID, _ change: @escaping @Sendable (inout NotebookSnapshot) -> Void) {
        listed.withValue { notebooks in
            guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
            change(&notebooks[index])
        }
    }
}

/// 지운 필사책의 기기 안 초안 버리기 대역 — 부른 순서를 함께 쓰는 기록에 남긴다.
final class ShelfDraftDiscarderSpy: NotebookDraftDiscarding {
    let events: LockIsolated<[String]>

    init(events: LockIsolated<[String]>) { self.events = events }

    func discardDrafts(notebook: NotebookID) async throws -> Int {
        events.withValue { $0.append("discard(\(notebook.rawValue))") }; return 0
    }
}

/// 분석 대역 — 보낸 이벤트를 모은다.
final class ShelfAnalyticsSpy: AnalyticsClient {
    struct Event: Equatable, Sendable {
        let name: String
        let parameters: [String: AnalyticsValue]
    }

    let events = LockIsolated<[Event]>([])

    func track(_ name: String, parameters: [String: AnalyticsValue]) { events.withValue { $0.append(Event(name: name, parameters: parameters)) } }
    func screen(_ name: String, parameters: [String: AnalyticsValue]) {}
}

/// iCloud 도착 신호 대역 — 시험이 도착 시각을 보낸다. 구독은 하나뿐이다.
final class ShelfArrivals: CloudImportArrivalClient {
    let stream: AsyncStream<Date>
    let continuation: AsyncStream<Date>.Continuation

    init() { (stream, continuation) = AsyncStream<Date>.makeStream() }

    func arrivals() -> AsyncStream<Date> { stream }
}

/// 바꿀 수 있는 편집 환경 대역 — 시트를 연 뒤 연결이 보류되는 경우를 만든다.
final class ShelfEditEnvironment: DrawingEditEnvironmentClient {
    let environment: LockIsolated<DrawingEditEnvironment>

    init(_ environment: DrawingEditEnvironment) { self.environment = LockIsolated(environment) }

    func current() async -> DrawingEditEnvironment { environment.value }
    func isCurrent(_ token: AccountServerWorkToken) async -> Bool { environment.value.serverWork == token }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// 코디네이터처럼 책장을 품고, 책장의 위임을 함께 쓰는 기록에 남기는 시험용 부모 — 지우기 순서(위임 → 지우기 → 초안 버리기)를 본다.
@Reducer
struct ShelfOrderRecorder {
    @ObservableState
    struct State: Equatable { var shelf: NotebookShelfFeature.State }
    enum Action { case shelf(NotebookShelfFeature.Action) }

    let events: LockIsolated<[String]>

    var body: some ReducerOf<Self> {
        Scope(state: \.shelf, action: \.shelf) {
            NotebookShelfFeature()
        }
        Reduce { _, action in
            if case let .shelf(.delegate(.currentNotebookChanged(notebook))) = action {
                events.withValue { $0.append("delegate(\(notebook.rawValue))") }
            }
            return .none
        }
    }
}

/// 연결 보류 환경 — 동기화 저장소 쓰기를 막는다(`SyncedWriteBlock.connectionHeld`).
private var heldEnvironment: DrawingEditEnvironment {
    var environment = DrawingEditEnvironment.ownedForTesting
    environment.connectionHeld = true
    return environment
}

/// 이 시험만의 UserDefaults 로 돌린다 — 지금 필사책 키(기기마다)가 다른 시험과 섞이지 않는다.
@MainActor
private func withShelfDefaults(_ operation: @MainActor (UserDefaults, String) async throws -> Void) async throws {
    let suite = "NotebookShelfFeatureTesting.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try await operation(defaults, suite)
}

/// 책장 TestStore — 시각 · UUID · 시계를 고정하고 저장소 · 편집 환경 · 분석 · 초안 · 도착을 대역으로 넣는다.
@MainActor
private func makeShelfStore(
    _ repository: ShelfRepositorySpy,
    defaults: UserDefaults,
    environment: any DrawingEditEnvironmentClient = StubDrawingEditEnvironment(.ownedForTesting),
    analytics: ShelfAnalyticsSpy = ShelfAnalyticsSpy(),
    discarder: ShelfDraftDiscarderSpy? = nil,
    arrivals: any CloudImportArrivalClient = StubCloudImportArrivalClient()
) -> TestStoreOf<NotebookShelfFeature> {
    TestStore(initialState: NotebookShelfFeature.State()) {
        NotebookShelfFeature()
    } withDependencies: {
        $0.defaultAppStorage = defaults
        $0.notebookRepository = repository
        $0.notebookDraftDiscarder = discarder
        $0.drawingEditEnvironment = environment
        $0.cloudImportArrivals = arrivals
        $0.analyticsClient = analytics
        $0.uuid = .constant(ShelfFixture.newUUID)
        $0.date = .constant(ShelfFixture.now)
        $0.continuousClock = ImmediateClock()
    }
}

/// 책장을 열어 목록을 읽은 상태로 만든다.
@MainActor
private func openShelf(_ store: TestStoreOf<NotebookShelfFeature>, expecting notebooks: [NotebookSnapshot]) async {
    await store.send(.view(.onAppear)) {
        $0.listRequestedAt = ShelfFixture.now
    }
    await store.receive(\.notebooksLoaded) {
        $0.notebooks = IdentifiedArray(uniqueElements: notebooks)
        $0.hasLoaded = true
    }
}

/// 이름 시트를 연다(「새 필사책」 카드 · 카드 메뉴의 「이름 바꾸기」) — 동기화 저장소에 쓸 수 있는 환경이다.
@MainActor
private func openEditor(_ store: TestStoreOf<NotebookShelfFeature>, _ purpose: NotebookShelfFeature.NameEditor.Purpose) async {
    switch purpose {
    case .create: await store.send(.view(.newNotebookTapped))
    case .rename(let notebook): await store.send(.view(.renameTapped(notebook)))
    }
    await store.receive(\.editorWriteChecked) {
        $0.editor = NotebookShelfFeature.NameEditor(purpose: purpose)
    }
}

/// 책장 아래 안내가 저절로 내려간다(`ImmediateClock`).
@MainActor
private func expectNoticeExpired(_ store: TestStoreOf<NotebookShelfFeature>) async {
    await store.receive(\.noticeExpired) {
        $0.notice = nil
    }
}

/// 카드 메뉴의 「필사책 지우기」 → 확인창의 「모두 지우기」.
@MainActor
private func confirmDelete(_ store: TestStoreOf<NotebookShelfFeature>, _ notebook: NotebookSnapshot) async {
    await store.send(.view(.deleteTapped(notebook.id))) {
        $0.deleteAlert = NotebookShelfFeature.deleteAlert(notebook, locale: AppLanguage.displayLocale())
    }
    await store.send(.deleteAlert(.presented(.confirm(notebook.id)))) {
        $0.deleteAlert = nil
        $0.isWorking = true
    }
}

// MARK: - 목록 · 고르기 · 관리

@Suite("책장 — 목록 · 고르기 · 만들기 · 이름 바꾸기 · 완료 표시")
@MainActor
struct NotebookShelfFeatureTesting {
    @Test("나타나면 필사책 목록을 읽어 카드로 보이고, 읽기 시작한 시각을 남긴다")
    func onAppearLoadsNotebooks() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook, ShelfFixture.thirdNotebook])
            let store = makeShelfStore(repository, defaults: defaults)

            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook, ShelfFixture.thirdNotebook])

            #expect(repository.reads.value == 1)
            #expect(store.state.currentNotebook == .default)
        }
    }

    @Test("목록을 읽지 못하면 「다시 시도」 를 두고, 다시 시도하면 읽는다")
    func loadFailureOffersRetry() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook])
            repository.failsReads.setValue(true)
            let store = makeShelfStore(repository, defaults: defaults)

            await store.send(.view(.onAppear)) {
                $0.listRequestedAt = ShelfFixture.now
            }
            await store.receive(\.notebooksLoadFailed) {
                $0.hasLoaded = true
                $0.loadFailed = true
            }

            repository.failsReads.setValue(false)
            await store.send(.view(.retryLoadTapped))
            await store.receive(\.notebooksLoaded) {
                $0.notebooks = [ShelfFixture.defaultNotebook]
                $0.loadFailed = false
            }
        }
    }

    @Test("iCloud 에서 받은 것이 들어오면 목록을 다시 읽는다 — 읽기 시작한 때보다 이른 도착(구독할 때 오는 마지막 import)은 다시 읽지 않는다")
    func cloudArrivalReloads() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook])
            let arrivals = ShelfArrivals()
            let store = makeShelfStore(repository, defaults: defaults, arrivals: arrivals)
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook])

            // 이미 읽은 목록에 든 도착 — 다시 읽지 않는다.
            arrivals.continuation.yield(ShelfFixture.now.addingTimeInterval(-60))
            await store.receive(\.cloudImportArrived)
            #expect(repository.reads.value == 1)

            // 다른 기기가 만든 필사책이 들어왔다.
            repository.listed.withValue { $0.append(ShelfFixture.secondNotebook) }
            arrivals.continuation.yield(ShelfFixture.now.addingTimeInterval(60))
            await store.receive(\.cloudImportArrived)
            await store.receive(\.notebooksLoaded) {
                $0.notebooks.append(ShelfFixture.secondNotebook)
            }
            #expect(repository.reads.value == 2)

            arrivals.continuation.finish()
            await store.finish()
        }
    }

    @Test("카드를 누르면 그 필사책을 고른다고 알리고(연결 보류 중에도 막지 않는다 — 지금 필사책 키만 바꾼다), 「닫기」 는 필사 화면으로 돌아가라고 알린다")
    func tappingCardChoosesNotebook() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])
            let store = makeShelfStore(repository, defaults: defaults, environment: StubDrawingEditEnvironment(heldEnvironment))
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])

            await store.send(.view(.notebookTapped(ShelfFixture.second)))
            await store.receive(\.delegate.notebookChosen, ShelfFixture.second)

            // 키는 코디네이터 → 필사 화면(`switchNotebook`)이 쓴다 — 책장은 쓰지 않는다(처음 읽을 때 저장된 기본값 그대로). 저장소에도 쓰지 않는다.
            #expect(defaults.string(forKey: "currentNotebookID") == NotebookID.default.rawValue)
            #expect(repository.calls.value.isEmpty)

            await store.send(.view(.backTapped))
            await store.receive(\.delegate.backToWriting)
        }
    }

    // MARK: 만들기 · 이름 바꾸기 · 완료 표시

    @Test("새 필사책 — 이름을 다듬어 지금 시각으로 만들고, 지금 필사책 키를 새 ID 로 쓴 뒤 분석을 한 번 남기고 고른다고 알린다")
    func createWritesKeyTracksAndChooses() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])
            let analytics = ShelfAnalyticsSpy()
            let store = makeShelfStore(repository, defaults: defaults, analytics: analytics)
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])
            let created = NotebookID.make(uuid: ShelfFixture.newUUID)

            await openEditor(store, .create)
            await store.send(.view(.editorSaveTapped("  세 번째 필사 \n"))) {
                $0.editor?.isSaving = true
            }
            await store.receive(\.created) {
                $0.editor = nil
                $0.$currentNotebookID.withLock { $0 = created.rawValue }
            }
            await store.receive(\.delegate.notebookChosen, created)

            #expect(repository.calls.value == [.create(created, name: "세 번째 필사", now: ShelfFixture.now)])
            #expect(defaults.string(forKey: "currentNotebookID") == created.rawValue)
            let completed = ShelfAnalyticsSpy.Event(
                name: AnalyticsEventName.featureComplete, parameters: ["feature_name": .string("Notebook"), "success": .bool(true)]
            )
            #expect(analytics.events.value == [completed])
        }
    }

    @Test("새 필사책을 만들지 못하면 시트에 남아 실패를 보이고, 키 · 분석 · 위임은 그대로다")
    func createFailureStaysInSheet() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook])
            repository.failsWrites.setValue(true)
            let analytics = ShelfAnalyticsSpy()
            let store = makeShelfStore(repository, defaults: defaults, analytics: analytics)
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook])

            await openEditor(store, .create)
            await store.send(.view(.editorSaveTapped("두 번째 필사"))) {
                $0.editor?.isSaving = true
            }
            await store.receive(\.editorSaveFailed) {
                $0.editor?.isSaving = false
                $0.editor?.failure = .saveFailed
            }

            #expect(defaults.string(forKey: "currentNotebookID") == NotebookID.default.rawValue)
            #expect(analytics.events.value.isEmpty)
        }
    }

    @Test("이름 바꾸기 — 앞뒤 공백을 자르고, 빈 이름 · 공백뿐 · 40자를 넘는 이름은 저장소를 부르지 않는다. 40자는 받는다")
    func renameValidatesName() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])
            let store = makeShelfStore(repository, defaults: defaults)
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])

            await openEditor(store, .rename(ShelfFixture.second))
            await store.send(.view(.editorSaveTapped("")))
            await store.send(.view(.editorSaveTapped("   \n ")))
            await store.send(.view(.editorSaveTapped(String(repeating: "가", count: 41))))
            #expect(repository.calls.value.isEmpty)

            let forty = String(repeating: "가", count: 40)
            await store.send(.view(.editorSaveTapped("  \(forty)\t"))) {
                $0.editor?.isSaving = true
            }
            await store.receive(\.renamed) {
                $0.editor = nil
            }
            await store.receive(\.notebooksLoaded) {
                $0.notebooks[id: ShelfFixture.second]?.name = forty
            }
            #expect(repository.calls.value == [.rename(ShelfFixture.second, name: forty, now: ShelfFixture.now)])
        }
    }

    @Test("지금 필사책의 이름을 바꾸면 필사 화면 헤더가 이름을 다시 읽게 알린다 — 같은 이름이면 쓰지 않고 시트만 닫는다")
    func renameCurrentNotifiesHeader() async throws {
        try await withShelfDefaults { defaults, _ in
            defaults.set(NotebookID.default.rawValue, forKey: "currentNotebookID")
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])
            let store = makeShelfStore(repository, defaults: defaults)
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])

            // 기본 필사책도 이름을 바꿀 수 있다(정보가 없으면 저장소가 만든다).
            await openEditor(store, .rename(.default))
            await store.send(.view(.editorSaveTapped("2026 시편"))) {
                $0.editor?.isSaving = true
            }
            await store.receive(\.renamed) {
                $0.editor = nil
            }
            await store.receive(\.delegate.currentNotebookChanged, .default)
            await store.receive(\.notebooksLoaded) {
                $0.notebooks[id: .default]?.name = "2026 시편"
            }

            // 다른 필사책은 헤더에 알리지 않는다. 같은 이름이면 저장소를 부르지 않는다.
            await openEditor(store, .rename(ShelfFixture.second))
            await store.send(.view(.editorSaveTapped(" 두 번째 필사 "))) {
                $0.editor = nil
            }
            #expect(repository.calls.value == [.rename(.default, name: "2026 시편", now: ShelfFixture.now)])
        }
    }

    @Test("완료로 표시 · 완료 취소는 지금 시각으로 저장하고 목록을 다시 읽는다 — 표시일 뿐이다")
    func completionToggles() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])
            let store = makeShelfStore(repository, defaults: defaults)
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])

            // 완료로 표시 → 완료 취소.
            for completed in [true, false] {
                await store.send(.view(.completionToggled(ShelfFixture.second))) {
                    $0.isWorking = true
                }
                await store.receive(\.completionChanged) {
                    $0.isWorking = false
                }
                await store.receive(\.notebooksLoaded) {
                    $0.notebooks[id: ShelfFixture.second]?.status = completed ? .completed : .active
                    $0.notebooks[id: ShelfFixture.second]?.completedAt = completed ? ShelfFixture.now : nil
                }
            }

            #expect(repository.calls.value == [
                .setCompleted(ShelfFixture.second, true, now: ShelfFixture.now),
                .setCompleted(ShelfFixture.second, false, now: ShelfFixture.now)
            ])
        }
    }
}

// MARK: - 지우기 · 쓰기 막음

@Suite("책장 — 지우기 · 동기화 저장소 쓰기 막음")
@MainActor
struct NotebookShelfDeleteTesting {
    @Test("지금 필사책을 지우면 키를 기본으로 → 위임(currentNotebookChanged(.default)) → 저장소 지우기 → 기기 안 초안 버리기 순서다")
    func deletingCurrentNotebookKeepsOrder() async throws {
        try await withShelfDefaults { defaults, suite in
            defaults.set(ShelfFixture.second.rawValue, forKey: "currentNotebookID")
            let events = LockIsolated<[String]>([])
            let repository = ShelfRepositorySpy(
                [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook, ShelfFixture.thirdNotebook], events: events, suiteName: suite
            )
            let store = TestStore(initialState: ShelfOrderRecorder.State(shelf: NotebookShelfFeature.State())) {
                ShelfOrderRecorder(events: events)
            } withDependencies: {
                $0.defaultAppStorage = defaults
                $0.notebookRepository = repository
                $0.notebookDraftDiscarder = ShelfDraftDiscarderSpy(events: events)
                $0.date = .constant(ShelfFixture.now)
                $0.continuousClock = ImmediateClock()
            }
            #expect(store.state.shelf.currentNotebook == ShelfFixture.second)

            await store.send(.shelf(.view(.onAppear))) {
                $0.shelf.listRequestedAt = ShelfFixture.now
            }
            await store.receive(\.shelf.notebooksLoaded) {
                $0.shelf.notebooks = [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook, ShelfFixture.thirdNotebook]
                $0.shelf.hasLoaded = true
            }
            await store.send(.shelf(.view(.deleteTapped(ShelfFixture.second)))) {
                $0.shelf.deleteAlert = NotebookShelfFeature.deleteAlert(ShelfFixture.secondNotebook, locale: AppLanguage.displayLocale())
            }
            await store.send(.shelf(.deleteAlert(.presented(.confirm(ShelfFixture.second))))) {
                $0.shelf.deleteAlert = nil
                $0.shelf.isWorking = true
            }
            await store.receive(\.shelf.deletePermitted) {
                $0.shelf.$currentNotebookID.withLock { $0 = NotebookID.default.rawValue }
            }
            await store.receive(\.shelf.delegate.currentNotebookChanged, .default)
            await store.receive(\.shelf.deleted) {
                $0.shelf.isWorking = false
                $0.shelf.notebooks.remove(id: ShelfFixture.second)
            }
            await store.receive(\.shelf.notebooksLoaded)

            let token = ShelfFixture.second.rawValue
            #expect(events.value == ["delegate(default)", "delete(\(token))", "discard(\(token))"])
            #expect(repository.keyAtDelete.value == NotebookID.default.rawValue)
            #expect(repository.calls.value == [.delete(ShelfFixture.second)])
        }
    }

    @Test("지금 필사책이 아닌 필사책을 지우면 키 · 위임은 그대로이고 그 필사책의 행 · 초안만 지운다")
    func deletingOtherNotebookKeepsCurrent() async throws {
        try await withShelfDefaults { defaults, _ in
            defaults.set(ShelfFixture.second.rawValue, forKey: "currentNotebookID")
            let events = LockIsolated<[String]>([])
            let repository = ShelfRepositorySpy(
                [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook, ShelfFixture.thirdNotebook], events: events
            )
            let store = makeShelfStore(repository, defaults: defaults, discarder: ShelfDraftDiscarderSpy(events: events))
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook, ShelfFixture.thirdNotebook])

            await confirmDelete(store, ShelfFixture.thirdNotebook)
            await store.receive(\.deletePermitted)
            await store.receive(\.deleted) {
                $0.isWorking = false
                $0.notebooks.remove(id: ShelfFixture.third)
            }
            await store.receive(\.notebooksLoaded)

            let token = ShelfFixture.third.rawValue
            #expect(events.value == ["delete(\(token))", "discard(\(token))"])
            #expect(defaults.string(forKey: "currentNotebookID") == ShelfFixture.second.rawValue)
        }
    }

    @Test("기본 필사책에는 지우기가 없다 — 지우기를 눌러도 확인창이 뜨지 않고, 확인이 와도 저장소를 부르지 않는다")
    func defaultNotebookCannotBeDeleted() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])
            let store = TestStore(initialState: {
                var initial = NotebookShelfFeature.State()
                initial.deleteAlert = NotebookShelfFeature.deleteAlert(ShelfFixture.defaultNotebook, locale: Locale(identifier: "ko"))
                return initial
            }()) {
                NotebookShelfFeature()
            } withDependencies: {
                $0.defaultAppStorage = defaults
                $0.notebookRepository = repository
                $0.date = .constant(ShelfFixture.now)
            }

            await store.send(.view(.deleteTapped(.default)))
            await store.send(.deleteAlert(.presented(.confirm(.default)))) {
                $0.deleteAlert = nil
            }
            #expect(repository.calls.value.isEmpty)
        }
    }

    @Test("지우기를 실패하면 안내를 띄우고 목록은 그대로다")
    func deleteFailureShowsNotice() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])
            repository.failsWrites.setValue(true)
            let store = makeShelfStore(repository, defaults: defaults)
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])

            await confirmDelete(store, ShelfFixture.secondNotebook)
            await store.receive(\.deletePermitted)
            await store.receive(\.deleteFailed) {
                $0.isWorking = false
                $0.notice = .deleteFailed
            }
            await expectNoticeExpired(store)
        }
    }

    // MARK: 동기화 저장소 쓰기 막음 — 연결 보류 · 계정 미확인이면 관리 동작을 저장소에 쓰지 않는다
    @Test("연결 보류 중에는 새 필사책 시트를 열지 않고 사유를 알린다 — 저장소 · 키 · 위임은 그대로다")
    func createIsBlockedBeforeSheet() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook])
            let store = makeShelfStore(repository, defaults: defaults, environment: StubDrawingEditEnvironment(heldEnvironment))
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook])

            await store.send(.view(.newNotebookTapped))
            await store.receive(\.editorWriteChecked) {
                $0.notice = .blocked(.connectionHeld)
            }
            await expectNoticeExpired(store)
            #expect(repository.calls.value.isEmpty)
            #expect(defaults.string(forKey: "currentNotebookID") == NotebookID.default.rawValue)
        }
    }

    @Test("시트를 연 뒤 연결이 보류되면 만들기를 저장소에 쓰지 않고 시트에 사유를 보인다 — 키 · 분석 · 위임은 그대로다")
    func createIsBlockedAtSave() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook])
            let environment = ShelfEditEnvironment(.ownedForTesting)
            let analytics = ShelfAnalyticsSpy()
            let store = makeShelfStore(repository, defaults: defaults, environment: environment, analytics: analytics)
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook])
            await openEditor(store, .create)

            environment.environment.setValue(heldEnvironment)
            await store.send(.view(.editorSaveTapped("두 번째 필사"))) {
                $0.editor?.isSaving = true
            }
            await store.receive(\.writeBlocked) {
                $0.editor?.isSaving = false
                $0.editor?.failure = .blocked(.connectionHeld)
            }

            #expect(repository.calls.value.isEmpty)
            #expect(defaults.string(forKey: "currentNotebookID") == NotebookID.default.rawValue)
            #expect(analytics.events.value.isEmpty)
        }
    }

    @Test("로그인하지 않았으면 지우기를 확인해도 저장소를 부르지 않고 지금 필사책 키 · 위임도 그대로다")
    func deleteIsBlockedWithoutAccount() async throws {
        try await withShelfDefaults { defaults, _ in
            defaults.set(ShelfFixture.second.rawValue, forKey: "currentNotebookID")
            let events = LockIsolated<[String]>([])
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook], events: events)
            let signedOut = DrawingEditEnvironment(accountState: .noAccount, serverWork: nil, knowledge: EraseEpochKnowledge())
            let store = makeShelfStore(
                repository, defaults: defaults, environment: StubDrawingEditEnvironment(signedOut),
                discarder: ShelfDraftDiscarderSpy(events: events)
            )
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])

            await confirmDelete(store, ShelfFixture.secondNotebook)
            await store.receive(\.writeBlocked) {
                $0.isWorking = false
                $0.notice = .blocked(.signedOut)
            }
            await expectNoticeExpired(store)

            #expect(repository.calls.value.isEmpty)
            #expect(events.value.isEmpty)
            #expect(defaults.string(forKey: "currentNotebookID") == ShelfFixture.second.rawValue)
        }
    }

    @Test("연결 보류 중에는 완료 표시 · 이름 바꾸기도 저장소에 쓰지 않는다")
    func completionAndRenameAreBlocked() async throws {
        try await withShelfDefaults { defaults, _ in
            let repository = ShelfRepositorySpy([ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])
            let store = makeShelfStore(repository, defaults: defaults, environment: StubDrawingEditEnvironment(heldEnvironment))
            await openShelf(store, expecting: [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook])

            await store.send(.view(.completionToggled(ShelfFixture.second))) {
                $0.isWorking = true
            }
            await store.receive(\.writeBlocked) {
                $0.isWorking = false
                $0.notice = .blocked(.connectionHeld)
            }
            await expectNoticeExpired(store)

            await store.send(.view(.renameTapped(ShelfFixture.second)))
            await store.receive(\.editorWriteChecked) {
                $0.notice = .blocked(.connectionHeld)
            }
            await expectNoticeExpired(store)
            #expect(repository.calls.value.isEmpty)
        }
    }
}

// MARK: - 이름 · 카드 문구

@Suite("책장 — 이름 제안 · 보이는 이름 · 카드 문구")
@MainActor
struct NotebookNamingTesting {
    private static let korean = Locale(identifier: "ko")
    private static let english = Locale(identifier: "en")

    @Test("서수 이름 1~12 — ko 「첫 번째 필사」 … 「열 번째 필사」 · 「11번째 필사」, en 「First Notebook」 · 「Notebook 2」")
    func ordinalNames() {
        let korean = (1...12).map { NotebookNaming.ordinalName($0, locale: Self.korean) }
        #expect(korean == [
            "첫 번째 필사", "두 번째 필사", "세 번째 필사", "네 번째 필사", "다섯 번째 필사", "여섯 번째 필사",
            "일곱 번째 필사", "여덟 번째 필사", "아홉 번째 필사", "열 번째 필사", "11번째 필사", "12번째 필사"
        ])
        let english = (1...12).map { NotebookNaming.ordinalName($0, locale: Self.english) }
        #expect(english == ["First Notebook"] + (2...12).map { "Notebook \($0)" })
    }

    @Test("새 필사책 이름 제안은 「필사책 수 + 1」 번째 — 기본 필사책 하나뿐이면 「두 번째 필사」, 이미 쓰는 이름이면 다음 서수")
    func suggestedNames() {
        #expect(NotebookNaming.suggestedName(existing: [ShelfFixture.defaultNotebook], locale: Self.korean) == "두 번째 필사")
        #expect(NotebookNaming.suggestedName(existing: [ShelfFixture.defaultNotebook], locale: Self.english) == "Notebook 2")
        #expect(NotebookNaming.suggestedName(existing: [NotebookSnapshot](), locale: Self.korean) == "두 번째 필사")
        let two = [ShelfFixture.defaultNotebook, ShelfFixture.secondNotebook]
        #expect(NotebookNaming.suggestedName(existing: two, locale: Self.korean) == "세 번째 필사")

        // 두 번째 필사책에 「세 번째 필사」 라고 이름을 붙였다 — 겹치지 않게 다음 서수를 제안한다.
        var renamed = ShelfFixture.secondNotebook
        renamed.name = "세 번째 필사"
        #expect(NotebookNaming.suggestedName(existing: [ShelfFixture.defaultNotebook, renamed], locale: Self.korean) == "네 번째 필사")
    }

    @Test("이름 검사 — 앞뒤 공백 · 줄바꿈을 자르고, 비었거나 40자를 넘으면 받지 않는다")
    func validatedNames() {
        #expect(NotebookNaming.validatedName("  시편 필사 \n") == "시편 필사")
        #expect(NotebookNaming.validatedName("") == nil)
        #expect(NotebookNaming.validatedName(" \t\n ") == nil)
        #expect(NotebookNaming.validatedName(String(repeating: "가", count: 40)) == String(repeating: "가", count: 40))
        #expect(NotebookNaming.validatedName(String(repeating: "가", count: 41)) == nil)
    }

    @Test("카드 문구 — 시작 월은 화면 언어의 연 · 월 서식, 쓴 절 수는 복수형")
    func cardTexts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
        let october = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9)))

        #expect(NotebookShelfView.startedText(october, calendar: calendar, locale: Self.korean) == "2026년 10월 시작")
        #expect(NotebookShelfView.startedText(october, calendar: calendar, locale: Self.english) == "Started October 2026")
        #expect(NotebookShelfView.writtenVersesText(12, locale: Self.korean) == "12절 필사")
        #expect(NotebookShelfView.writtenVersesText(1, locale: Self.english) == "1 verse written")
        #expect(NotebookShelfView.writtenVersesText(12, locale: Self.english) == "12 verses written")
    }

    @Test("막은 안내는 즐겨찾기와 같은 사유 문장을 붙인다")
    func blockedMessages() {
        #expect(NotebookShelfView.blockedMessage(.signedOut, locale: Self.korean) == "지금은 필사책을 만들거나 고칠 수 없어요. iCloud 에 로그인하지 않았어요")
        #expect(
            NotebookShelfView.blockedMessage(.signedOut, locale: Self.english)
                == "You can't create or change notebooks right now. You're not signed in to iCloud"
        )
        #expect(NotebookShelfView.noticeMessage(.deleteFailed, locale: Self.english) == "Couldn't delete the notebook")
        #expect(NotebookShelfView.failureMessage(.saveFailed, purpose: .create, locale: Self.korean) == "필사책을 만들지 못했어요")
        #expect(NotebookShelfView.failureMessage(.saveFailed, purpose: .rename(ShelfFixture.second), locale: Self.english) == "Couldn't rename the notebook")
    }

    @Test("지우기 확인창 — 「『<이름>』 과 그 필기를 모두 지울까요?」 · 「되돌릴 수 없어요.」, 이름 없는 필사책은 화면 언어의 기본 표시")
    func deleteAlertTexts() {
        func alert(_ texts: [String], _ notebook: NotebookID) -> AlertState<NotebookShelfFeature.Action.DeleteAlert> {
            AlertState { TextState(verbatim: texts[0]) } actions: {
                ButtonState(role: .cancel) { TextState(verbatim: texts[1]) }
                ButtonState(role: .destructive, action: .confirm(notebook)) { TextState(verbatim: texts[2]) }
            } message: { TextState(verbatim: texts[3]) }
        }
        #expect(NotebookShelfFeature.deleteAlert(ShelfFixture.secondNotebook, locale: Self.korean) == alert(
            ["『두 번째 필사』 과 그 필기를 모두 지울까요?", "취소", "모두 지우기", "되돌릴 수 없어요."], ShelfFixture.second
        ))
        #expect(NotebookShelfFeature.deleteAlert(ShelfFixture.thirdNotebook, locale: Self.english) == alert(
            ["Delete “Untitled Notebook” and all its writing?", "Cancel", "Delete All", "This can't be undone."], ShelfFixture.third
        ))
    }
}
