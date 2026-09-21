//
//  CarveDetailVerseImageTesting.swift
//  CarveFeatureTest
//
//  절 이미지 저장(시안 G1 · G2) — 필사 화면 배선. 절 메뉴가 넘긴 필기 칸에 본문 · 본문 모양 · 출처를 더해 이미지를 만들고,
//  사진 보관함에 넣은 결과를 셋(성공 안내 · 다시 시도가 있는 실패 안내 · 권한 확인창)으로 알리는지.
//  `CarveDetailFeature.State` 는 Equatable 이 아니라 TestStore 대신 실제 Store 로 상태 전이를 본다.
//

import ClientInterfaces
import Domain
import Foundation
import Testing
import UIKit

import ComposableArchitecture

@testable import CarveFeature

// MARK: - 스텁

/// 사진 보관함 스텁. `steps` 를 앞에서부터 꺼내 결과를 정하고, 비어 있으면 추가에 성공한다.
private final class PhotoLibrarySpy: PhotoLibraryClient, @unchecked Sendable {
    enum Step: Sendable {
        case added
        case permissionDenied
        case fail
    }

    struct Boom: Error {}

    let added = LockIsolated<[Data]>([])
    let steps: LockIsolated<[Step]>
    /// 다음 추가를 `release()` 까지 붙잡는다 — 저장이 끝나기 전에 다시 누르는 경우.
    private let holdNext = LockIsolated(false)
    private let gate = LockIsolated<AsyncStream<Void>.Continuation?>(nil)

    init(steps: [Step] = []) {
        self.steps = LockIsolated(steps)
    }

    var isHolding: Bool { gate.value != nil }

    func holdNextAdd() {
        holdNext.setValue(true)
    }

    func release() {
        gate.withValue { $0?.yield(); $0?.finish(); $0 = nil }
    }

    func addImage(_ imageData: Data) async throws -> PhotoLibraryAddOutcome {
        if holdNext.withValue({ let hold = $0; $0 = false; return hold }) {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            gate.setValue(continuation)
            for await _ in stream { break }
        }
        added.withValue { $0.append(imageData) }
        let step = steps.withValue { $0.isEmpty ? Step.added : $0.removeFirst() }
        switch step {
        case .added: return .added
        case .permissionDenied: return .permissionDenied
        case .fail: throw Boom()
        }
    }
}

/// 받은 내용을 기록하고 정해 둔 데이터를 돌려주는 이미지 렌더러.
private final class RendererSpy: @unchecked Sendable {
    let rendered = LockIsolated<[VerseImageContent]>([])
    private let result: Data?

    init(result: Data? = Data("png".utf8)) {
        self.result = result
    }

    var client: VerseImageRenderer {
        VerseImageRenderer { [rendered, result] content in
            rendered.withValue { $0.append(content) }
            return result
        }
    }
}

// MARK: - 필사 화면

@Suite("G1 · G2 — 절 이미지 저장 배선")
@MainActor
struct CarveDetailVerseImageTesting {
    private static let chapter = BibleChapter(title: .psalms, chapter: 23)
    private static let sentence = "여호와는 나의 목자시니 내가 부족함이 없으리로다"
    private static let handwriting = VerseImageHandwriting(
        verse: 1,
        writingSize: CGSize(width: 320, height: 60),
        underlineAnchors: [30, 60],
        inkData: Data([7])
    )
    private static let request = CarveDetailFeature.Action.scope(.chapterCanvasAction(.delegate(.imageSaveRequested(handwriting))))

    private static func state() -> CarveDetailFeature.State {
        var state = CarveDetailFeature.State.initialState
        state.sentenceWithDrawingState = [
            SentencesWithDrawingFeature.State(sentence: BibleVerse(title: chapter, verse: 1, sentence: sentence), drawing: nil)
        ]
        return state
    }

    private func makeStore(
        photos: PhotoLibrarySpy,
        renderer: RendererSpy,
        clock: TestClock<Duration> = TestClock(),
        openedURLs: LockIsolated<[URL]> = LockIsolated([]),
        state: CarveDetailFeature.State? = nil
    ) -> StoreOf<CarveDetailFeature> {
        // 기본 인자는 격리되지 않은 문맥에서 계산돼 MainActor 인 `state()` 를 부를 수 없다 — 안에서 채운다.
        Store(initialState: state ?? Self.state()) {
            CarveDetailFeature()
        } withDependencies: {
            $0.photoLibraryClient = photos
            $0.verseImageRenderer = renderer.client
            $0.continuousClock = clock
            $0.openURL = OpenURLEffect { url in
                openedURLs.withValue { $0.append(url) }
                return true
            }
        }
    }

    /// 효과가 끝나기를 기다린다. 제한 시간 안에 조건이 참이 되지 않으면 실패로 기록한다.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("조건이 제한 시간 안에 참이 되지 않았다", sourceLocation: sourceLocation)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func isFailureNotice(_ notice: CarveDetailFeature.ImageSaveNotice?) -> Bool {
        if case .failed = notice { return true }
        return false
    }

    @Test("그 절 본문 · 지금 본문 모양 · 출처에 캔버스가 넘긴 필기 칸을 더해 이미지를 만들어 사진에 넣고, 성공 안내가 잠깐 뜬다")
    func savesRenderedImageAndShowsNotice() async throws {
        let photos = PhotoLibrarySpy()
        let renderer = RendererSpy()
        let clock = TestClock()
        let store = makeStore(photos: photos, renderer: renderer, clock: clock)

        store.send(Self.request)
        try await waitUntil { store.imageSaveNotice == .saved }

        #expect(renderer.rendered.value == [VerseImageContent(
            sentence: Self.sentence,
            setting: store.sentenceSetting,
            reference: "시편 23장 1절 · 개역개정",
            handwriting: Self.handwriting
        )])
        #expect(photos.added.value == [Data("png".utf8)])
        #expect(store.isSavingVerseImage == false)

        await clock.advance(by: CarveDetailFeature.imageSavedNoticeDuration)
        try await waitUntil { store.imageSaveNotice == nil }
    }

    @Test("사진 추가 권한이 꺼져 있으면 안내 대신 확인창을 띄우고, 「설정 열기」 는 앱 설정을 연다")
    func permissionDeniedShowsAlertThatOpensSettings() async throws {
        let photos = PhotoLibrarySpy(steps: [.permissionDenied])
        let openedURLs = LockIsolated<[URL]>([])
        let store = makeStore(photos: photos, renderer: RendererSpy(), openedURLs: openedURLs)
        let settingsURL = try #require(URL(string: UIApplication.openSettingsURLString))

        store.send(Self.request)
        try await waitUntil { store.photoPermissionAlert != nil }
        #expect(store.imageSaveNotice == nil)

        store.send(.photoPermissionAlert(.presented(.openSettings)))
        try await waitUntil { !openedURLs.value.isEmpty }

        #expect(openedURLs.value == [settingsURL])
        #expect(store.photoPermissionAlert == nil)
    }

    @Test("사진에 넣지 못하면 「다시 시도」 안내가 뜨고, 다시 시도하면 같은 내용으로 다시 저장한다")
    func failureOffersRetryWithSameContent() async throws {
        let photos = PhotoLibrarySpy(steps: [.fail])
        let renderer = RendererSpy()
        let store = makeStore(photos: photos, renderer: renderer)

        store.send(Self.request)
        try await waitUntil { isFailureNotice(store.imageSaveNotice) }
        let content = try #require(renderer.rendered.value.first)
        #expect(store.imageSaveNotice == .failed(content))

        store.send(.view(.imageSaveRetryTapped))
        try await waitUntil { store.imageSaveNotice == .saved }

        #expect(renderer.rendered.value == [content, content])
        #expect(photos.added.value.count == 2)
    }

    @Test("이미지를 그리지 못하면 사진에 넣지 않고 실패 안내를 띄운다")
    func renderFailureDoesNotTouchPhotos() async throws {
        let photos = PhotoLibrarySpy()
        let store = makeStore(photos: photos, renderer: RendererSpy(result: nil))

        store.send(Self.request)
        try await waitUntil { isFailureNotice(store.imageSaveNotice) }

        #expect(photos.added.value.isEmpty)
    }

    @Test("저장하는 동안 다시 눌러도 한 번만 저장한다")
    func repeatedRequestWhileSavingIsIgnored() async throws {
        let photos = PhotoLibrarySpy()
        let renderer = RendererSpy()
        let store = makeStore(photos: photos, renderer: renderer)
        photos.holdNextAdd()

        store.send(Self.request)
        try await waitUntil { photos.isHolding }
        store.send(Self.request)
        photos.release()
        try await waitUntil { store.imageSaveNotice == .saved }

        #expect(renderer.rendered.value.count == 1)
        #expect(photos.added.value.count == 1)
    }

    @Test("이미지 저장 안내가 뜨면 즐겨찾기 안내를 내린다 — 안내 자리는 하나다")
    func imageNoticeReplacesFavoriteNotice() async throws {
        var state = Self.state()
        state.favoriteNotice = .added
        let store = makeStore(photos: PhotoLibrarySpy(), renderer: RendererSpy(), state: state)

        store.send(Self.request)
        try await waitUntil { store.imageSaveNotice == .saved }

        #expect(store.favoriteNotice == nil)
    }
}
