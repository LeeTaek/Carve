//
//  TranslationSwitchTesting.swift
//  CarveFeatureTest
//
//  영어 현지화 결정 9 · 13 · 19 — 번역본 전환. 헤더 제목 메뉴에서 번역본을 고르면 지금 장의 번역본만 바뀌고 같은 권 · 장 · 보던 절로 간다.
//  그 번역본에 없는 절이면 바로 앞 절로, 전환은 장 이동과 같은 경로(캔버스 저장 flush → 새 장 load)를 탄다.
//  `CarveNavigationFeature.State` · `CarveDetailFeature.State` 는 Equatable 이 아니라 상태 전이는 `reduce(into:)` 와 실제 Store 로,
//  캔버스의 flush · load 순서는 `ChapterCanvasFeature` TestStore 로 본다.
//

@testable import CarveFeature
import CoreGraphics
import Domain
import Foundation
import PencilKit
import Testing
import UIKit

import ComposableArchitecture

// MARK: - 스텁

/// 번역본마다 다른 본문을 돌려주는 스텁. BSB 마태복음 17장에는 21절이 없다(실제 본문과 같다 — 사본에 없는 절).
private struct TranslationTextStub: BibleTextClient {
    func fetch(chapter: BibleChapter) throws -> [BibleVerse] {
        let missing: Set<Int> = chapter.translation == .BSB && chapter.title == .matthew && chapter.chapter == 17 ? [21] : []
        return (1...27).filter { !missing.contains($0) }.map { verse in
            BibleVerse(title: chapter, verse: verse, sentence: "\(chapter.translation.rawValue) \(chapter.chapter):\(verse)")
        }
    }
}

/// 초안을 어느 번역본으로 읽었는지 남기는 초안 저장소. 읽기는 늘 빈 목록이다.
private struct TranslationRecordingDraftStore: VerseDraftStore {
    let requested = LockIsolated<[Translation]>([])

    func saveDraft(_ draft: VerseDraft, superseding: [VerseDraftRef]) async throws -> LocalPreservationWriter.WriteOutcome {
        .written
    }

    func drafts(in scope: AccountScope, chapter: BibleChapter, translation: Translation) async throws -> [VerseDraft] {
        requested.withValue { $0.append(translation) }
        return []
    }

    func removeDraft(_ key: VerseDraftKey, scope: AccountScope, ifRevision revision: Int) async throws {}

    func markDraftStored(_ key: VerseDraftKey, scope: AccountScope, throughRevision revision: Int, contentFingerprint: String?) async throws {}

    func currentGeneration() async -> UInt64? { 0 }
}

// MARK: - 헬퍼

/// 비어 있는 UserDefaults 묶음으로 `operation` 을 돌린다 — 지금 장(`title`)이 저장되지 않은 처음 설치와 같다.
private func withEmptyAppStorage<Value>(
    preferredLanguages: [String]? = nil,
    _ operation: (UserDefaults) throws -> Value
) throws -> Value {
    let suite = "TranslationSwitchTesting.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    return try withDependencies {
        $0.defaultAppStorage = defaults
        if let preferredLanguages { $0.preferredLanguages = preferredLanguages }
    } operation: {
        try operation(defaults)
    }
}

/// 저장된 지금 장(`title`)을 읽는다.
private func storedTitle(in defaults: UserDefaults) throws -> BibleChapter {
    let data = try #require(defaults.data(forKey: "title"))
    return try JSONDecoder().decode(BibleChapter.self, from: data)
}

// MARK: - 시험 — 전환

@Suite("영어 현지화 결정 9 — 번역본 전환")
@MainActor
struct TranslationSwitchTesting {
    private static let nkrvMatthew17 = BibleChapter(title: .matthew, chapter: 17)
    private static let bsbMatthew17 = BibleChapter(title: .matthew, chapter: 17, translation: .BSB)
    private static let now = Date(timeIntervalSince1970: 1_000)

    // MARK: 헬퍼

    private func reduce(_ state: inout CarveNavigationFeature.State, _ action: CarveNavigationFeature.Action) {
        _ = CarveNavigationFeature().reduce(into: &state, action: action)
    }

    private func reduce(_ state: inout CarveDetailFeature.State, _ action: CarveDetailFeature.Action) {
        _ = CarveDetailFeature().reduce(into: &state, action: action)
    }

    private static func sentences(_ chapter: BibleChapter, verses: [Int]) -> [BibleVerse] {
        verses.map { BibleVerse(title: chapter, verse: $0, sentence: "본문 \($0)") }
    }

    /// 전 절의 밑줄을 한 줄씩 잰 배치 — 레이아웃이 완성된다.
    private static func oneLineGeometry(_ chapter: BibleChapter, verses: [Int]) -> [SentencesWithDrawingFeature.State.ID: VerseRowGeometry] {
        var batch: [SentencesWithDrawingFeature.State.ID: VerseRowGeometry] = [:]
        for verse in verses {
            batch[SentencesWithDrawingFeature.State.rowID(chapter: chapter, verse: verse)] = VerseRowGeometry(underlineOffsets: [30])
        }
        return batch
    }

    /// 본문을 읽고 레이아웃까지 완성된 필사 화면 상태.
    private func measuredDetail(_ state: inout CarveDetailFeature.State, chapter: BibleChapter, verses: [Int]) {
        reduce(&state, .view(.layoutHostingChanged(writingWidth: 372)))
        reduce(&state, .setSentence(Self.sentences(chapter, verses: verses)))
        reduce(&state, .view(.verseGeometryMeasured(Self.oneLineGeometry(chapter, verses: verses))))
    }

    /// 그 절이 보이는 맨 위에 오도록 스크롤했다고 알린다 — 캔버스가 보내는 `current` 는 콘텐츠 y 의 음수다.
    private func scroll(_ state: inout CarveDetailFeature.State, toVerse verse: Int) throws {
        let region = try #require(state.chapterLayout.layout?.region(verse: verse))
        reduce(&state, .view(.headerAnimation(0, -region.captureRect.midY)))
    }

    /// 효과가 끝나기를 기다린다. 제한 시간 안에 조건이 참이 되지 않으면 실패로 기록한다.
    private func waitUntil(
        timeout: Duration = .seconds(3),
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

    // MARK: 헤더 제목의 번역본 고르기(결정 19)

    @Test("번역본을 고르면 지금 장의 번역본만 바뀌고 같은 권 · 장 · 보던 절로 간다 — 헤더도 같은 장을 본다")
    func selectingTranslationKeepsBookChapterAndVerse() throws {
        try withEmptyAppStorage { defaults in
            var state = CarveNavigationFeature.State.initialState
            state.$currentTitle.withLock { $0 = Self.nkrvMatthew17 }
            measuredDetail(&state.carveDetailState, chapter: Self.nkrvMatthew17, verses: Array(1...27))
            try scroll(&state.carveDetailState, toVerse: 12)
            #expect(state.carveDetailState.viewingVerse == 12)
            state.columnVisibility = .all
            state.drawnChapters = [.matthew: [1, 17]]
            // 헤더 제목을 눌러 연 번역본 고르기 팝오버에서 고른다.
            state.carveDetailState.headerState.isTranslationPickerPresented = true

            reduce(&state, .scope(.carveDetailAction(.scope(.headerAction(.view(.translationSelected(.KJV)))))))

            let kjv = BibleChapter(title: .matthew, chapter: 17, translation: .KJV)
            #expect(state.currentTitle == kjv)
            #expect(state.carveDetailState.headerState.currentTitle == kjv)
            let stored = try storedTitle(in: defaults)
            #expect(stored == kjv)
            #expect(state.carveDetailState.scrollTargetVerse == 12)
            // 보던 절은 보이는 맨 위 절이므로 맨 위에 다시 둔다 — 아래쪽에 두면 바꿀 때마다 앞 절로 밀린다(EN-M1).
            #expect(state.carveDetailState.scrollTargetAnchor == .top)
            // 장 이동과 같다 — 탐색을 닫고, 장 목록 선택은 지금 장이다.
            #expect(state.columnVisibility == .detailOnly)
            #expect(!state.carveDetailState.headerState.isNavigationPresented)
            #expect(state.selectedTitle == .matthew)
            #expect(state.selectedChapter == 17)
            // 필사 기록은 번역본마다 따로다 — 이전 번역본으로 칠한 장 목록을 남기지 않는다.
            #expect(state.drawnChapters.isEmpty)
            // 고르면 고르기 팝오버는 닫힌다.
            #expect(!state.carveDetailState.headerState.isTranslationPickerPresented)
        }
    }

    @Test("지금 번역본을 다시 고르면 아무것도 바꾸지 않고 고르기 팝오버만 닫는다")
    func selectingCurrentTranslationIsNoOp() throws {
        try withEmptyAppStorage { _ in
            var state = CarveNavigationFeature.State.initialState
            state.$currentTitle.withLock { $0 = Self.bsbMatthew17 }
            state.columnVisibility = .all
            state.drawnChapters = [.matthew: [17]]
            state.carveDetailState.headerState.isTranslationPickerPresented = true

            reduce(&state, .scope(.carveDetailAction(.scope(.headerAction(.view(.translationSelected(.BSB)))))))

            #expect(state.currentTitle == Self.bsbMatthew17)
            #expect(state.columnVisibility == .all)
            #expect(state.drawnChapters == [.matthew: [17]])
            #expect(state.carveDetailState.scrollTargetVerse == nil)
            #expect(!state.carveDetailState.headerState.isTranslationPickerPresented)
        }
    }

    @Test("번역본을 바꾼 뒤의 장 이동 · 다음 장 · 이전 장은 그 번역본을 그대로 둔다")
    func chapterMovesKeepTranslation() throws {
        try withEmptyAppStorage { _ in
            var state = CarveNavigationFeature.State.initialState
            state.$currentTitle.withLock { $0 = BibleChapter(title: .genesis, chapter: 50, translation: .KJV) }

            reduce(&state, .scope(.carveDetailAction(.scope(.headerAction(.view(.moveToNext))))))
            #expect(state.currentTitle == BibleChapter(title: .exodus, chapter: 1, translation: .KJV))

            reduce(&state, .scope(.carveDetailAction(.scope(.headerAction(.view(.moveToBefore))))))
            #expect(state.currentTitle == BibleChapter(title: .genesis, chapter: 50, translation: .KJV))

            // 장 목록 버튼은 지금 번역본의 장을 보낸다(`CarveNavigationView.chapterButton`).
            reduce(&state, .moveToChapter(BibleChapter(title: .john, chapter: 3, translation: .KJV)))
            #expect(state.currentTitle == BibleChapter(title: .john, chapter: 3, translation: .KJV))
        }
    }

    @Test("번역본 고르기 항목 이름은 약칭과 전체 이름을 함께 적고, 둘이 같으면 한 번만 적는다")
    func translationMenuTitles() {
        let korean = Locale(identifier: "ko")
        let english = Locale(identifier: "en")
        #expect(HeaderView.translationMenuTitle(.NKRV, locale: korean) == "개역개정")
        #expect(HeaderView.translationMenuTitle(.KJV, locale: korean) == "KJV · King James Version")
        #expect(HeaderView.translationMenuTitle(.BSB, locale: korean) == "BSB · Berean Standard Bible")
        #expect(HeaderView.translationMenuTitle(.NKRV, locale: english) == "NKRV · New Korean Revised Version")
        #expect(HeaderView.translationMenuTitle(.KJV, locale: english) == "KJV · King James Version")
        // 고르기 목록은 `Translation.allCases` 순서다(`TranslationPickerView`).
        #expect(Translation.allCases == [.NKRV, .KJV, .BSB])
    }

    // MARK: 보던 절 · 앞 절

    @Test("보던 절은 보이는 맨 위에 걸친 절이다 — 맨 위면 첫 절, 끝을 넘으면 마지막 절, 레이아웃이 없으면 nil")
    func viewingVerseFollowsScrollPosition() throws {
        var state = CarveDetailFeature.State.initialState
        #expect(state.viewingVerse == nil)

        measuredDetail(&state, chapter: Self.nkrvMatthew17, verses: Array(1...5))
        #expect(state.viewingVerse == 1)

        try scroll(&state, toVerse: 3)
        #expect(state.viewingVerse == 3)

        reduce(&state, .view(.headerAnimation(0, -100_000)))
        #expect(state.viewingVerse == 5)

        // 아직 옮기지 않은 이동 목표가 있으면 그 절이다 — 새 장을 읽는 사이 다시 바꿔도 처음 보던 절을 잃지 않는다.
        state.scrollTargetVerse = 4
        #expect(state.viewingVerse == 4)
    }

    @Test("이동할 절이 그 번역본에 없으면 바로 앞 절, 합쳐진 절의 뒤 번호면 그 행으로 간다")
    func scrollableVerseFallsBackToPreviousVerse() {
        let bsbRows = IdentifiedArray(uniqueElements: Self.sentences(Self.bsbMatthew17, verses: (1...27).filter { $0 != 21 })
            .map(SentencesWithDrawingFeature.State.init(sentence:)))
        #expect(CarveDetailFeature.scrollableVerse(for: 21, in: bsbRows) == 20)
        #expect(CarveDetailFeature.scrollableVerse(for: 22, in: bsbRows) == 22)
        #expect(CarveDetailFeature.scrollableVerse(for: 99, in: bsbRows) == 27)

        // 신명기 6:18-19 처럼 합쳐진 절은 앞 번호 행 하나다.
        let merged = IdentifiedArray(uniqueElements: [
            BibleVerse(title: BibleChapter(title: .deuteronomy, chapter: 6), verse: 17, sentence: "17"),
            BibleVerse(title: BibleChapter(title: .deuteronomy, chapter: 6), verse: 18, verseEnd: 19, sentence: "18-19"),
            BibleVerse(title: BibleChapter(title: .deuteronomy, chapter: 6), verse: 20, sentence: "20")
        ].map(SentencesWithDrawingFeature.State.init(sentence:)))
        #expect(CarveDetailFeature.scrollableVerse(for: 19, in: merged) == 18)
        // 앞 절이 없으면 첫 절, 행이 없으면 nil.
        #expect(CarveDetailFeature.scrollableVerse(for: 1, in: merged) == 17)
        #expect(CarveDetailFeature.scrollableVerse(for: 3, in: []) == nil)
    }

    @Test("개역개정 마 17:21 에서 BSB 로 바꾸면 같은 장을 BSB 로 읽고 17:20 으로 스크롤한다 — 본문 · 측정 · 캔버스가 BSB 장을 본다")
    func switchingToBSBScrollsToPreviousVerseWhenMissing() async throws {
        let suite = "TranslationSwitchTesting.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        try await withDependencies {
            $0.defaultAppStorage = defaults
        } operation: {
            let initial = CarveNavigationFeature.State.initialState
            initial.$currentTitle.withLock { $0 = Self.nkrvMatthew17 }
            let spy = RepositorySpy()
            let store = Store(initialState: initial) {
                CarveNavigationFeature()
            } withDependencies: {
                $0.bibleTextClient = TranslationTextStub()
                $0.drawingRepository = spy
                $0.drawingCodec = CanvasTestSupport.codec(results: LockIsolated([]))
                $0.favoriteVerseRepository = FavoriteRepositorySpy()
                $0.uuid = .incrementing
                $0.date = .constant(Self.now)
                $0.continuousClock = TestClock()
            }

            // 개역개정 마 17 을 읽고 재서, 21절을 보이는 맨 위에 둔다.
            store.send(.scope(.carveDetailAction(.view(.fetchSentence))))
            try await waitUntil { store.carveDetailState.sentenceWithDrawingState.count == 27 }
            store.send(.scope(.carveDetailAction(.view(.layoutHostingChanged(writingWidth: 372)))))
            store.send(.scope(.carveDetailAction(.view(.verseGeometryMeasured(Self.oneLineGeometry(Self.nkrvMatthew17, verses: Array(1...27)))))))
            let region = try #require(store.carveDetailState.chapterLayout.layout?.region(verse: 21))
            store.send(.scope(.carveDetailAction(.view(.headerAnimation(0, -region.captureRect.midY)))))
            #expect(store.carveDetailState.viewingVerse == 21)
            try await waitUntil { spy.loadedChapters.value.contains(Self.nkrvMatthew17) }

            store.send(.scope(.carveDetailAction(.scope(.headerAction(.view(.translationSelected(.BSB)))))))
            try await waitUntil { spy.loadedChapters.value.last == Self.bsbMatthew17 }
            try await waitUntil { store.carveDetailState.sentenceWithDrawingState.count == 26 }

            do {
                let detail = store.carveDetailState
                #expect(store.currentTitle == Self.bsbMatthew17)
                // 본문은 BSB 로 읽었고 21절이 없다. 행 · 측정 · 캔버스가 모두 BSB 장이다.
                #expect(detail.sentenceWithDrawingState.allSatisfy { $0.sentence.title == Self.bsbMatthew17 })
                #expect(!detail.sentenceWithDrawingState.contains { $0.sentence.verse == 21 })
                #expect(detail.chapterLayout.chapter == Self.bsbMatthew17)
                #expect(detail.chapterCanvas.chapter == Self.bsbMatthew17)
                #expect(detail.favoriteChapter == Self.bsbMatthew17)
                #expect(detail.scrollTargetVerse == 21)
            }

            // 행이 바뀌면 뷰가 스크롤을 낸다(`CarveDetailView` 의 onChange) — 없는 21절 대신 20절로 간다.
            store.send(.scope(.carveDetailAction(.scrollToTop)))
            try await waitUntil { store.carveDetailState.chapterCanvas.scrollRequest?.verse == 20 }
            #expect(store.carveDetailState.chapterCanvas.scrollRequest?.anchor == .top)
            #expect(store.carveDetailState.scrollTargetVerse == nil)
            #expect(store.carveDetailState.scrollTargetAnchor == .bottom)
        }
    }

    @Test("외부 진입(위젯 · 차트 · 실행 인자)의 이동 목표는 아래쪽 정렬이다 — 번역본 전환이 남긴 맨 위 정렬을 물려받지 않는다")
    func externalScrollTargetKeepsBottomAnchor() async throws {
        var state = CarveDetailFeature.State.initialState
        state.scrollTargetAnchor = .top

        reduce(&state, .setScrollTarget(BibleVerse(title: Self.nkrvMatthew17, verse: 5, sentence: "본문 5")))
        #expect(state.scrollTargetVerse == 5)
        #expect(state.scrollTargetAnchor == .bottom)

        // 행이 들어오면 뷰가 `scrollToTop` 을 낸다 — 캔버스 스크롤 요청은 효과로 가므로 실제 Store 로 돌린다.
        reduce(&state, .setSentence(Self.sentences(Self.nkrvMatthew17, verses: Array(1...10))))
        let store = Store(initialState: state) { CarveDetailFeature() }
        store.send(.scrollToTop)
        try await waitUntil { store.chapterCanvas.scrollRequest != nil }
        #expect(store.chapterCanvas.scrollRequest?.verse == 5)
        #expect(store.chapterCanvas.scrollRequest?.anchor == .bottom)
        #expect(store.scrollTargetVerse == nil)
    }

    @Test("scrollOffset(bringingTopOf:) 는 소유 영역 위쪽을 헤더 바로 아래(offset + top inset)에 1pt 안쪽으로 두고, 양 끝은 클램프한다")
    func scrollOffsetBringingTopAlignsUnderHeaderAndClamps() {
        let inset = UIEdgeInsets(top: 100, left: 0, bottom: 50, right: 0)
        let offset = ChapterCanvasController.scrollOffset(
            bringingTopOf: CGRect(x: 0, y: 900, width: 300, height: 100),
            viewportHeight: 800, contentInset: inset, contentHeight: 3_000
        )
        // 900 + 1 − 100 = 801 — 보이는 맨 위(801 + 100 = 901)가 소유 영역 [900, 1000) 안이다.
        #expect(offset == 801)

        let first = ChapterCanvasController.scrollOffset(
            bringingTopOf: CGRect(x: 0, y: 0, width: 300, height: 100),
            viewportHeight: 800, contentInset: inset, contentHeight: 3_000
        )
        #expect(first == -99)

        let last = ChapterCanvasController.scrollOffset(
            bringingTopOf: CGRect(x: 0, y: 2_900, width: 300, height: 100),
            viewportHeight: 800, contentInset: inset, contentHeight: 3_000
        )
        #expect(last == 2_250)   // 장 끝 근처 절은 맨 위까지 올라가지 않는다
    }

    @Test("맨 위 정렬로 옮긴 절이 다음 전환의 보던 절이다 — 번역본을 거듭 바꿔도 같은 절에 머문다(EN-M1)")
    func topAnchoredVerseIsNextViewingVerse() throws {
        var state = CarveDetailFeature.State.initialState
        measuredDetail(&state, chapter: Self.nkrvMatthew17, verses: Array(1...27))
        let layout = try #require(state.chapterLayout.layout)
        let inset = UIEdgeInsets(top: 120, left: 0, bottom: 60, right: 0)
        for verse in [2, 12, 20] {
            let region = try #require(layout.region(verse: verse))
            let offset = ChapterCanvasController.scrollOffset(
                bringingTopOf: region.captureRect,
                viewportHeight: 1_000, contentInset: inset, contentHeight: layout.totalHeight + 1_000
            )
            // 캔버스가 알리는 위치는 −(offset + inset.top) 이다(`scrollViewDidScroll`).
            reduce(&state, .view(.headerAnimation(0, -(offset + inset.top))))
            #expect(state.viewingVerse == verse)
        }
    }

    @Test("번역본만 바뀐 장의 행 id 는 번역본마다 다르다 — 앱 언어와 무관한 rawValue 형식이다")
    func rowIDDiffersByTranslation() {
        let nkrv = SentencesWithDrawingFeature.State.rowID(chapter: BibleChapter(title: .genesis, chapter: 1), verse: 1)
        let kjv = SentencesWithDrawingFeature.State.rowID(chapter: BibleChapter(title: .genesis, chapter: 1, translation: .KJV), verse: 1)
        let bsb = SentencesWithDrawingFeature.State.rowID(chapter: BibleChapter(title: .genesis, chapter: 1, translation: .BSB), verse: 1)
        #expect(nkrv == "NKRV/1-01Genesis.txt/1/1")
        #expect(kjv == "KJV/1-01Genesis.txt/1/1")
        #expect(Set([nkrv, kjv, bsb]).count == 3)

        // 같은 권 · 장 · 절이라도 번역본이 다르면 다른 행이다 — 뷰가 행을 새로 만들고 장 전환 스크롤을 낸다.
        let nkrvRow = SentencesWithDrawingFeature.State(sentence: BibleVerse(title: BibleChapter(title: .genesis, chapter: 1), verse: 1, sentence: "태초에"))
        let kjvRow = SentencesWithDrawingFeature.State(
            sentence: BibleVerse(title: BibleChapter(title: .genesis, chapter: 1, translation: .KJV), verse: 1, sentence: "In the beginning")
        )
        #expect(nkrvRow != kjvRow)
    }

}

// MARK: - 시험 — 번역본 귀속 · 처음 기본값

@Suite("영어 현지화 결정 9 · 4 — 전환 뒤 번역본 귀속과 처음 기본값")
@MainActor
struct TranslationSwitchAttributionTesting: EditSessionTestHelpers {
    private static let now = Date(timeIntervalSince1970: 1_000)

    // MARK: 저장 flush → load

    @Test("번역본을 바꾸면 이전 번역본 장의 미저장분을 그 장으로 저장(flush)한 뒤 새 번역본 장을 읽는다")
    func switchFlushesPreviousTranslationBeforeLoading() async {
        let spy = RepositorySpy()
        spy.applyFailures.setValue([.persistenceFailed("offline")])
        let store = CanvasTestSupport.makeStore(spy: spy, results: LockIsolated([CanvasTestSupport.createResult("1")]))
        await CanvasTestSupport.compose(store)   // 개역개정 요나 2장

        await store.send(.editEnded(CanvasTestSupport.edit("1")))
        await store.receive(\.mutationsPrepared)
        await store.receive(\.saveFinished)      // 실패 → 미저장분이 남는다
        #expect(store.state.pendingMutations.count == 1)

        let kjv = BibleChapter(title: CanvasTestSupport.chapter.title, chapter: CanvasTestSupport.chapter.chapter, translation: .KJV)
        spy.holdNextLoadCall()
        await store.send(.load(chapter: kjv, expectedVerseCount: 3))
        await store.receive(\.saveFinished)
        // 미저장분은 쓴 장(개역개정)으로 갔다 — 새 번역본 장으로 옮겨 가지 않는다.
        #expect(spy.applied.value.last?.chapter == CanvasTestSupport.chapter)
        #expect(spy.applied.value.last?.chapter.translation == .NKRV)
        #expect(store.state.pendingMutations.isEmpty)
        // 새 번역본 장은 아직 읽는 중이다.
        #expect(spy.loadedChapters.value == [CanvasTestSupport.chapter])

        spy.releaseLoad()
        await store.receive(\.drawingsLoaded)
        #expect(spy.loadedChapters.value == [CanvasTestSupport.chapter, kjv])
        #expect(store.state.chapter == kjv)
        #expect(store.state.loadedDrawings == [])
    }

    // MARK: 번역본 귀속 — 초안 · 스냅샷

    @Test("KJV 장의 초안은 KJV 로 읽는다 — 저장 키와 같은 번역본이다")
    func draftsAreReadInChapterTranslation() async throws {
        let drafts = TranslationRecordingDraftStore()
        let environment = confirmed(accountA, 0)
        let kjv = BibleChapter(title: .jonah, chapter: 2, translation: .KJV)

        _ = try await ChapterCanvasFeature.loadDrafts(from: drafts, environment: environment, chapter: kjv)
        _ = await ChapterCanvasFeature.loadBeforeConnectionDrafts(from: drafts, environment: environment, chapter: kjv)

        #expect(!drafts.requested.value.isEmpty)
        #expect(drafts.requested.value.allSatisfy { $0 == .KJV })
        // 초안 키도 장의 번역본을 따른다.
        #expect(VerseDraftKey(sessionID: "s", chapter: kjv, verse: 1).translation == "KJV")
    }

    @Test("저장 명령을 겹친 행은 장의 번역본이다 — KJV 장의 loadedDrawings 에 개역개정 행이 섞이지 않는다")
    func overlaidSnapshotsCarryChapterTranslation() {
        let existing = VerseDrawingSnapshot(
            verse: 1, rowID: CanvasTestSupport.rowA, isPresent: true, updateDate: nil,
            lineData: Data([1]), drawingVersion: 3, metadata: nil, translation: .KJV
        )
        let mutations: [VerseDrawingMutation] = [
            .create(verse: 2, rowID: CanvasTestSupport.newRow, data: Data([2]), metadata: CanvasTestSupport.metadata()),
            .clear(verse: 1, rowID: CanvasTestSupport.rowA)
        ]

        let overlaid = withDependencies {
            $0.date = .constant(Self.now)
        } operation: {
            ChapterCanvasFeature().overlay([existing], with: mutations, translation: .KJV)
        }
        #expect(overlaid.count == 2)
        #expect(overlaid.allSatisfy { $0.translation == .KJV })

        // 번역본을 넘기지 않은 호출부는 스냅샷의 번역본을 따른다.
        let inferred = withDependencies {
            $0.date = .constant(Self.now)
        } operation: {
            ChapterCanvasFeature().overlay([existing], with: [mutations[0]])
        }
        #expect(inferred.allSatisfy { $0.translation == .KJV })
    }

    @Test("대기 중인 편집으로 만든 지금 필기 행은 그 편집의 장 번역본이다")
    func pendingInkSnapshotCarriesChapterTranslation() throws {
        let kjv = BibleChapter(title: .jonah, chapter: 2, translation: .KJV)
        var state = ChapterCanvasFeature.State(chapter: kjv)
        state.loadedDrawings = []
        state.activeRowIDs = [2: CanvasTestSupport.newRow]
        state.pendingMutations = [CanvasTestSupport.newRow: PendingDrawingMutation(
            revision: 1, chapter: kjv,
            mutation: .create(verse: 2, rowID: CanvasTestSupport.newRow, data: Self.inkData(), metadata: CanvasTestSupport.metadata())
        )]

        let snapshot = try #require(ChapterCanvasFeature.currentInkSnapshot(verse: 2, state: state))
        #expect(snapshot.translation == .KJV)
        #expect(snapshot.rowID == CanvasTestSupport.newRow)
    }

    // MARK: 처음 기본값

    @Test("저장된 장이 없으면 첫 선호 언어가 한국어일 때 개역개정, 아니면 BSB 창세기 1장으로 시작한다", arguments: [
        (["ko-KR", "en-US"], Translation.NKRV),
        (["en-US", "ko-KR"], Translation.BSB),
        (["ja-JP"], Translation.BSB),
        ([], Translation.BSB)
    ])
    func firstLaunchFollowsPreferredLanguages(languages: [String], expected: Translation) throws {
        try withEmptyAppStorage(preferredLanguages: languages) { defaults in
            let state = CarveNavigationFeature.State.initialState
            let first = BibleChapter(title: .genesis, chapter: 1, translation: expected)
            #expect(state.currentTitle == first)
            #expect(state.carveDetailState.headerState.currentTitle == first)
            let stored = try storedTitle(in: defaults)
            #expect(stored == first)
        }
    }

    @Test("저장된 장이 있으면 선호 언어와 상관없이 그대로다 — 기존 사용자는 개역개정을 유지한다")
    func storedChapterWinsOverPreferredLanguages() throws {
        try withEmptyAppStorage(preferredLanguages: ["en-US"]) { defaults in
            // 2.0.0 이 남긴 옛 JSON(translation 키 없음).
            defaults.set(Data(#"{"title":"1-19Psalms.txt","chapter":23}"#.utf8), forKey: "title")
            let state = CarveNavigationFeature.State.initialState
            #expect(state.currentTitle == BibleChapter(title: .psalms, chapter: 23, translation: .NKRV))
            #expect(HeaderFeature.State.initialState.currentTitle == BibleChapter(title: .psalms, chapter: 23, translation: .NKRV))
        }
    }

    /// 실제 획이 하나 있는 `PKDrawing` 데이터 — 빈 Data 는 "획 없음" 으로 판정된다.
    private static func inkData() -> Data {
        PKDrawing(strokes: [
            OwnershipTestSupport.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 40, y: 5), seed: 3, creationTime: 1_000)
        ]).dataRepresentation()
    }
}
