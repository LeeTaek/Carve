//
//  CarveDetailView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import SwiftUI

import ComposableArchitecture

@ViewAction(for: CarveDetailFeature.self)
public struct CarveDetailView: View {
    @Bindable public var store: StoreOf<CarveDetailFeature>
    @Environment(\.scenePhase) private var scenePhase
    @State private(set) var halfWidth: CGFloat = 0
    /// 행들의 실측 콜백을 모아 런루프 한 번에 한 액션으로 보내는 수집기 (Phase 2).
    /// 참조 객체이므로 `@State` 는 수명만 잡아 줄 뿐, 값이 바뀌어도 뷰를 다시 그리지 않는다.
    @State private var geometryCollector = VerseGeometryCollector()
    /// 뷰포트(스크롤 영역) 높이. 캔버스 지연 생성 범위 계산용.
    @State private var viewportHeight: CGFloat = 0
    /// 스크롤 콘텐츠 상단의 "Scroll" 좌표 (스크롤하면 음수). `offsetY` 콜백으로 갱신.
    @State private var contentMinY: CGFloat = 0
    /// `PKCanvasView` 를 실제로 만든 행. **한 번 활성화되면 유지**한다 (`LazyVStack` 이 만든 행을 버리지 않던 것과 같은 의미).
    ///
    /// Phase 2 실측: 비지연 `VStack` 에서 캔버스 176개를 진입 시점에 전부 만들면 시편 119편 진입에
    /// CPU ≈14 s · footprint ≈550 MB (시뮬레이터 Debug) 가 들어 설계 §18-5 의 (B)표 기준을 한 자릿수 이상 넘는다.
    /// 텍스트 행(측정에 필요한 것)은 즉시 만들고, 비싼 캔버스만 뷰포트 근처에서 만든다.
    @State private var activeCanvasIDs: Set<SentencesWithDrawingFeature.State.ID> = []

    /// 캔버스를 미리 만들어 둘 범위 — 뷰포트 위아래로 이 배수만큼.
    private static let canvasActivationMargin: CGFloat = 1.5
    
    public init(store: StoreOf<CarveDetailFeature>) {
        self.store = store
    }
    
    public var body: some View {
        /// iOS 17.5 이상에서 Apple Pencil 더블탭으로 지우개/이전 펜 타입을 전환하는 래핑 뷰 적용
        if #available(iOS 17.5, *) {
            applyPencilDoubleTapView()
                .overlay(alignment: .top) {
                    HeaderView(store: store.scope(state: \.headerState,
                                                  action: \.scope.headerAction))
                }
                .overlay(alignment: .bottom) { layoutDebugHUD }
                .toolbar(.hidden, for: .navigationBar)
        } else {
            detailScroll
                .overlay(alignment: .top) {
                    HeaderView(store: store.scope(state: \.headerState,
                                                  action: \.scope.headerAction))
                }
                .overlay(alignment: .bottom) { layoutDebugHUD }
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Phase 2 측정용 무인 시나리오 (Debug 전용). 실행 인자가 없으면 아무것도 하지 않는다.
    private func startDebugScenarioIfNeeded() {
        #if DEBUG
        if ChapterLayoutDebugScenario.isScrollEnabled {
            Task { @MainActor in
                await ChapterLayoutDebugScenario.runScroll(
                    verses: { store.sentenceWithDrawingState.map(\.sentence.verse) },
                    scrollTo: { verse in
                        if store.usesSingleCanvas {
                            store.send(.scope(.chapterCanvasAction(.scrollToVerse(verse))))
                        } else if let row = store.sentenceWithDrawingState.first(where: { $0.sentence.verse == verse }) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                store.proxy?.scrollTo(row.id, anchor: .bottom)
                            }
                        }
                    }
                )
            }
        }
        if ChapterLayoutDebugScenario.isNextChapterEnabled {
            Task { @MainActor in
                await ChapterLayoutDebugScenario.runNextChapter {
                    store.send(.scope(.headerAction(.view(.moveToNext))))
                }
            }
        }
        #endif
    }

    /// Phase 2 디버그 HUD. Debug 빌드에서 `-ChapterLayoutOverlay` 실행 인자가 있을 때만 보인다.
    @ViewBuilder
    private var layoutDebugHUD: some View {
        #if DEBUG
        if ChapterLayoutDebugFlags.isOverlayEnabled {
            ChapterLayoutDebugHUD(measurement: store.chapterLayout, lastEdit: lastEditForOverlay)
        }
        #endif
    }

    #if DEBUG
    /// 마지막 편집 절의 drawing bounds 를 콘텐츠 좌표로 옮긴 값. 절 캔버스 로컬 좌표에 실측 frame 원점을 더한다.
    private var lastEditForOverlay: (verse: Int, bounds: CGRect)? {
        guard let id = store.lastEditedVerseID,
              let row = store.sentenceWithDrawingState[id: id],
              let local = row.canvasState.lastDrawingBounds,
              let frame = store.chapterLayout.measuredFrames[row.sentence.verse] else { return nil }
        return (row.sentence.verse, local.offsetBy(dx: frame.minX, dy: frame.minY))
    }
    #endif
    
    
    @available(iOS 17.5, *)
    private func applyPencilDoubleTapView() -> some View {
        detailScroll
            .onPencilDoubleTap { _ in
                let isEraser = (store.headerState.palatteSetting.pencilConfig.pencilType == .monoline)
                if isEraser {
                    send(.switchToPreviousPenType)
                } else {
                    send(.switchToEraser)
                }
            }
    }
    
    private var detailScroll: some View {
        // 폭은 ScrollView 가 아니라 바깥 컨테이너에서 읽는다.
        // 세로 ScrollView 는 내용이 제안 폭보다 넓으면 가로로 함께 넓어지므로, 행 폭이 halfWidth 의 함수인 이상
        // "행 폭 → ScrollView 폭 → halfWidth → 행 폭" 이 발산한다 (Phase 2 실측: 372 → 376.7 → 381.3 → …, 고정점 1120).
        // LazyVStack 은 제안 폭을 그대로 보고해 이 순환이 드러나지 않았을 뿐이다.
        GeometryReader { container in
            Group {
                if store.usesSingleCanvas {
                    singleCanvasBody
                } else {
                    scrollBody
                }
            }
                .onAppear {
                    geometryCollector.onFlush = { batch in
                        send(.verseGeometryMeasured(batch))
                    }
                    send(.fetchSentence)
                    startDebugScenarioIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { send(.appWillResignActive) }
                }
                .onChange(of: container.size.width, initial: true) { _, width in
                    let half = width / 2
                    guard half > 0, half != halfWidth else { return }
                    halfWidth = half
                    // 필사 컬럼 폭 = 절 캔버스 폭 = ChapterLayout.writingWidth (Phase 2)
                    send(.layoutHostingChanged(writingWidth: half))
                }
                .onChange(of: container.size.height, initial: true) { _, height in
                    viewportHeight = height
                    updateActiveCanvases()
                }
        }
    }

    /// 뷰포트 근처(위아래 `canvasActivationMargin` 배)의 행을 캔버스 활성 집합에 더한다. 빼지는 않는다.
    ///
    /// 행 위치는 실측 frame(`chapterLayout.measuredFrames`, 콘텐츠 좌표)을 쓴다. "Scroll" 좌표로 옮기려면
    /// 콘텐츠 상단(`contentMinY`)과 헤더 padding(`headerHeight`)을 더한다.
    private func updateActiveCanvases() {
        guard viewportHeight > 0 else { return }
        let frames = store.chapterLayout.measuredFrames
        guard !frames.isEmpty else { return }
        let margin = viewportHeight * Self.canvasActivationMargin
        let visible = (-margin)...(viewportHeight + margin)
        let contentOrigin = contentMinY + store.headerState.headerHeight
        var added: Set<SentencesWithDrawingFeature.State.ID> = []
        for row in store.sentenceWithDrawingState where !activeCanvasIDs.contains(row.id) {
            guard let frame = frames[row.sentence.verse] else { continue }
            let top = contentOrigin + frame.minY
            let bottom = contentOrigin + frame.maxY
            if bottom >= visible.lowerBound && top <= visible.upperBound {
                added.insert(row.id)
            }
        }
        guard !added.isEmpty else { return }
        activeCanvasIDs.formUnion(added)
    }

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                contentView
                    .padding(.top, store.headerState.headerHeight)
                    .offsetY { previous, current in
                        contentMinY = current
                        updateActiveCanvases()
                        delay {
                            send(.headerAnimation(previous, current))
                        }
                    }
                    .onChange(of: store.sentenceWithDrawingState) {
                        // 장이 바뀌면 활성 집합도 새로 시작한다 (id 가 장마다 다르므로 남겨 둬도 무해하지만 계속 자란다).
                        activeCanvasIDs = []
                        send(.setProxy(proxy))
                    }
                    .onChange(of: store.chapterLayout.measuredFrames) {
                        // 실측 frame 이 도착한 뒤에야 어떤 행이 뷰포트 근처인지 알 수 있다.
                        updateActiveCanvases()
                    }
//                    // ✅ Canvas를 contentView에 overlay로 올려서 높이/레이아웃을 완전히 동일하게 맞춘다.
//                    // 이렇게 하면 Pencil hover/다운 시점에 Canvas만 별도로 "커지는" 레이아웃 흔들림을 줄일 수 있다.
//                    .overlay {
//                        CombinedCanvasView(
//                            store: self.store.scope(
//                                state: \.canvasState,
//                                action: \.scope.canvasAction
//                            ),
//                            onInkingChanged: { isInking in
//                                self.isInking = isInking
//                            }
//                        )
//                        .border(.red)
//                        .id(store.canvasState.chapter)
//                        .frame(width: halfWidth)
//                        .frame(
//                            maxWidth: .infinity,
//                            maxHeight: .infinity,
//                            alignment: store.isLeftHanded ? .leading : .trailing
//                        )
//                        .background(
//                            GeometryReader { proxy in
//                                Color.clear
//                                    .allowsHitTesting(false)
//                                    .onAppear {
//                                        let frame = proxy.frame(in: .named("CanvasSpace"))
//                                        send(.canvasFrameChanged(frame))
//                                    }
//                                    .onChange(of: proxy.frame(in: .named("CanvasSpace"))) { _, frame in
//                                        // 최종 레이아웃 기준 프레임을 항상 반영 (split/fullscreen 전환 시 좌표계 어긋남 방지)
//                                        send(.canvasFrameChanged(frame))
//                                    }
//                            }
//                        )
//                    }
                    .coordinateSpace(name: "CanvasSpace")
            }
            .onTapGesture {
                send(.tapForHeaderHidden)
            }
            .onTwoFingerDoubleTap {
                send(.twoFingerDoubleTapForUndo)
            }
            .coordinateSpace(name: "Scroll")
        }
    }
    
    /// Phase 3 — 단일 Canvas (B 구조). `PKCanvasView` 가 유일한 스크롤 뷰이고 텍스트 컬럼은 그 안에 있다.
    ///
    /// 컬럼은 N-Canvas 경로와 **같은 행 뷰**를 캔버스 없이(`isCanvasActive: false`) 쓴다. 실측·게이트·오버레이도 같다.
    /// 헤더는 콘텐츠를 밀지 않고 `contentInset.top` 으로 비우므로 컬럼에 상단 padding 을 주지 않는다.
    private var singleCanvasBody: some View {
        ChapterCanvasView(
            store: store.scope(state: \.chapterCanvas, action: \.scope.chapterCanvasAction),
            display: ChapterCanvasView.Display(store.chapterCanvas),
            topInset: store.headerState.headerHeight,
            column: AnyView(verseColumn(isCanvasActive: { _ in false })),
            onScroll: { previous, current in
                delay {
                    send(.headerAnimation(previous, current))
                }
            }
        )
        .onTapGesture {
            send(.tapForHeaderHidden)
        }
        .onTwoFingerDoubleTap {
            send(.twoFingerDoubleTapForUndo)
        }
    }

    /// Phase 2 — `LazyVStack` 을 비지연 `VStack` 으로 전환 (설계 §6-1 · rev.15).
    ///
    /// 전 절의 geometry 가 있어야 장 전체 레이아웃이 성립하므로 보이는 절만 만드는 지연 스택을 쓸 수 없다.
    /// 즉시 만드는 것은 **텍스트 행**(본문·밑줄·frame 실측)까지이고, 비싼 `PKCanvasView` 는 `activeCanvasIDs` 로
    /// 뷰포트 근처에서만 만든다 — 실측 결과 캔버스까지 즉시 만들면 진입 비용이 (B)표 기준을 한 자릿수 넘었다 (설계 §20-8).
    /// 간격은 `ChapterLayoutHosting` 상수로 명시해 `ChapterLayoutBuilder` 가 같은 값으로 좌표를 예측하게 한다.
    private var contentView: some View {
        verseColumn(isCanvasActive: { activeCanvasIDs.contains($0) })
    }

    /// 절 행 컬럼 — N-Canvas 경로와 단일 Canvas 경로가 공유한다. 차이는 행에 `PKCanvasView` 를 두는지뿐이다.
    private func verseColumn(
        isCanvasActive: @escaping (SentencesWithDrawingFeature.State.ID) -> Bool
    ) -> some View {
        VStack(spacing: ChapterLayoutHosting.rowSpacing) {
            // 폭을 모르는 첫 패스에서는 행을 만들지 않는다 — 176개 행을 폭 0 으로 한 번 더 배치·실측하는 낭비를 막는다.
            if halfWidth > 0 {
                ForEach(
                    store.scope(state: \.sentenceWithDrawingState,
                                action: \.scope.sentenceWithDrawingAction),
                    id: \.state.id
                ) { childStore in
                    SentencesWithDrawingView(
                        store: childStore,
                        halfWidth: $halfWidth,
                        isLayoutReady: store.isLayoutReady,
                        isCanvasActive: isCanvasActive(childStore.id),
                        onUnderlineLayoutChange: { id, layout in
                            // 실측 콜백은 행마다 따로 오지만 액션은 수집기가 한 틱에 하나로 모은다.
                            geometryCollector.reportUnderlineOffsets(
                                id: id,
                                offsets: VerseTextFeature.makeUnderlineOffsets(
                                    from: layout,
                                    sentenceSetting: store.sentenceSetting
                                )
                            )
                        },
                        onTitleHeightChange: { id, height in
                            geometryCollector.reportTitleHeight(id: id, height: height)
                        },
                        onCanvasFrameInRowChange: { id, frame in
                            geometryCollector.reportCanvasFrameInRow(id: id, frame: frame)
                        }
                    )
                    // 부모가 다시 그려져도(헤더 애니메이션 등) 입력이 같은 행은 body 를 건너뛴다.
                    // 비지연 VStack 에서는 행 176개가 전부 살아 있어 이 생략이 없으면 매 갱신이 행 수만큼 비싸진다.
                    .equatable()
                    // 행 frame 은 **바깥 트리**에서 잰다 — 행 안은 중첩 호스팅이라 ChapterContent 공간을 보지 못한다.
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(ChapterLayoutHosting.coordinateSpaceName))
                    } action: { [id = childStore.id] frame in
                        geometryCollector.reportRowFrame(id: id, frame: frame)
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        // 콘텐츠 폭을 컨테이너 폭에 고정한다. `VStack` 은 내용 폭을 그대로 보고하므로(`LazyVStack` 과 다름)
        // 이 고정이 없으면 위의 발산 순환과 "빈 내용 → 폭 0" 이 그대로 일어난다 (Phase 2 실측).
        .frame(width: halfWidth * 2)
        // 레이아웃 좌표계의 원점. 헤더 padding·스크롤 offset 은 이 공간 밖이다.
        .coordinateSpace(name: ChapterLayoutHosting.coordinateSpaceName)
        .overlay(alignment: .topLeading) { layoutDebugOverlay }
        .id("\(store.sentenceSetting)-\(halfWidth)")
    }

    /// Phase 2 디버그 오버레이 — `writingRect` / `captureRect` / `underlineAnchors` / 실측 frame / dirtyBounds.
    @ViewBuilder
    private var layoutDebugOverlay: some View {
        #if DEBUG
        if ChapterLayoutDebugFlags.isOverlayEnabled {
            ChapterLayoutDebugOverlay(
                measurement: store.chapterLayout,
                dirtyBounds: lastEditForOverlay?.bounds,
                contentWidth: halfWidth * 2
            )
        }
        #endif
    }
    
    /// 헤더 스크롤 애니메이션 등 과도한 이벤트 호출을 방지하기 위한 딜레이
    private func delay(
        to delay: TimeInterval = 0.1,
        _ action: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}


#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: {
            CarveDetailFeature()
        }
    )
    CarveDetailView(store: store)
}
