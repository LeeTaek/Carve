//
//  CarveDetailFeature.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/30/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Combine
import Domain
import Resources
import SwiftUI
import PencilKit

import ComposableArchitecture

@Reducer
public struct CarveDetailFeature {
    @ObservableState
    public struct State {
        /// 헤더 상태
        public var headerState: HeaderFeature.State
        /// 성경 구절 상태 List
        public var verseRowState: IdentifiedArrayOf<VerseRowFeature.State> = []
        /// 캔버스 상태
        public var canvasState: CombinedCanvasFeature.State = .initialState
        /// ScrollView 위치 제어용 프록시
        public var proxy: ScrollViewProxy?
        /// 마지막으로 사용한 펜 종류(펜슬 더블탭시 전환용)
        var lastUsedPencil: PKInkingTool.InkType = .pencil
        /// global 좌표계 기준 CombinedCanvasView의 frame (Canvas 기준 verse 별 rect 계산용)
        var canvasGlobalFrame: CGRect = .zero
        /// 특정 Verse로 스크롤 필요할 때 사용
        public var pendingScrollVerse: BibleVerse?
        
        /// 성경 문장 출력시 자간 폰트 등 설정
        @Shared(.appStorage("sentenceSetting")) public var sentenceSetting: SentenceSetting = .initialState
        /// 왼손잡이용 레이아웃 여부
        @Shared(.appStorage("isLeftHanded")) public var isLeftHanded: Bool = false
        
        public static let initialState = State(
            headerState: .initialState
        )
    }
    @Dependency(\.drawingData) var drawingContext
    
    public enum Action: ViewAction, CarveToolkit.ScopeAction {
        /// 화면 최상단으로 스크롤
        case scrollToTop
        case setScrollTarget(BibleVerse)
        case scrollToVerse
        /// 문장 설정/레이아웃 변경으로 텍스트 레이아웃을 재측정해야 할 때
        case invalidateTextLayout
        case view(View)
        case scope(ScopeAction)
        
        case setFetchedSentence(chapter: BibleChapter, verses: [BibleVerse])
        
        @CasePathable
        public enum View {
            /// 성경 구절 fetch
            case fetchSentence
            /// 스크롤에 따른 헤더 애니메이션
            case headerAnimation(CGFloat, CGFloat)
            /// 텍스트 레이아웃 재측정을 디바운스하여 요청
            case invalidateTextLayoutDebounced
            /// scrollView proxy 설정
            case setProxy(ScrollViewProxy)
            /// 펜을 지우개로 전환
            case switchToEraser
            /// 펜 타입을 이전으로 전환
            case switchToPreviousPenType
            /// 한 손가락 탭 액션: 헤더 노출/숨김
            case tapForHeaderHidden
            /// 두손가락 더블탭 액션: undo
            case twoFingerDoubleTapForUndo
            /// 밑줄 레이아웃 계산 (ForEachReducer missing element warning 회피를 위해 VerseRow가 아닌 상위에서 처리)
            case underlineLayoutChanged(id: VerseRowFeature.State.ID, layout: Text.LayoutKey.Value)
        }
    }

    @CasePathable
    public enum ScopeAction {
        case verseRowAction(IdentifiedActionOf<VerseRowFeature>)
        case headerAction(HeaderFeature.Action)
        case canvasAction(CombinedCanvasFeature.Action)
    }
    
    /// 비동기 작업 취소용 작업
    enum CancelID: Hashable {
        /// 성경 불러올떄
        case fetchBible(title: BibleChapter)
        /// sentenceSetting 변경 관찰
        case observeSentenceSetting
        /// 텍스트 레이아웃 재측정 디바운스
        case invalidateTextLayout
    }
    
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.headerState,
              action: \.scope.headerAction) {
            HeaderFeature()
        }
        Scope(state: \.canvasState,
              action: \.scope.canvasAction) {
            CombinedCanvasFeature()
        }

        Reduce { state, action in
            switch action {
            case .view(.headerAnimation(let previous, let current)):
                return .send(.scope(.headerAction(.headerAnimation(previous, current))))

            case .invalidateTextLayout:
                guard !state.verseRowState.isEmpty else { return .none }
                for index in state.verseRowState.indices {
                    state.verseRowState[index].verseTextState.preferenceVersion = UUID()
                }
                return .none

            case .view(.invalidateTextLayoutDebounced):
                return .run { send in
                    // 레이아웃 변화가 연속으로 발생할 때 최종 상태만 반영한다.
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    await send(.invalidateTextLayout)
                }
                .cancellable(id: CancelID.invalidateTextLayout, cancelInFlight: true)
                
            case .view(.fetchSentence):
                let oldChapter = state.canvasState.chapter
                                
                return .merge(
                    .cancel(id: CancelID.fetchBible(title: oldChapter)),
                    handleFetchSentence(state: &state),
                    observeSentenceSetting(state: state)
                )
                
            case .setFetchedSentence(let chapter, let verses):
                state.verseRowState = IdentifiedArrayOf(
                    uniqueElements: verses.map { VerseRowFeature.State(sentence: $0) }
                )
                
                state.canvasState = .init(chapter: chapter, drawingRect: [:])
                
                // 3) Drawing 데이터 fetch 트리거
                return .send(.scope(.canvasAction(.fetchDrawingData)))

            case .view(.underlineLayoutChanged(let id, let layout)):
                guard var row = state.verseRowState[id: id] else { return .none }

                let setting = row.verseTextState.sentenceSetting
                let offsets = VerseTextFeature.makeUnderlineOffsets(
                    from: layout,
                    sentenceSetting: setting
                )
                guard offsets != row.verseTextState.underlineOffsets else { return .none }

                row.verseTextState.underlineOffsets = offsets
                row.layoutVersion &+= 1
                state.verseRowState[id: id] = row

                let verse = row.sentence.verse
                return .send(.scope(.canvasAction(
                    .verseUnderlineOffsetsUpdated(verse: verse, offsets: offsets)
                )))
                
            case .view(.setProxy(let proxy)):
                state.proxy = proxy
                return .send(.scrollToTop)
                
            case .scrollToTop:
                guard let id = state.verseRowState.first?.id else { return .none }
                withAnimation(.easeInOut(duration: 0.5)) {
                    state.proxy?.scrollTo(id, anchor: .bottom)
                }
                
                return .run { send in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    await send(.scrollToVerse)
                }
                
            case .setScrollTarget(let verse):
                state.pendingScrollVerse = verse
                return .none
                
            case .scrollToVerse:
                return scrollToPendingVerseIfPossible(state: &state)


            case .view(.switchToEraser):
                // monoline을 지우개로 사용
                state.lastUsedPencil = state.headerState.palatteSetting.pencilConfig.pencilType
                return .send(.scope(.headerAction(.palatteAction(.view(.setPencilType(.monoline))))))
                
            case .view(.switchToPreviousPenType):
                // 지우개인 경우 기본 펜으로
                return .send(
                    .scope(.headerAction(.palatteAction(.view(.setPencilType(state.lastUsedPencil)))))
                )
                
            case .scope(.headerAction(.palatteAction(.view(.setPencilType(let penType))))):
                guard penType != .monoline,
                      penType != state.lastUsedPencil
                else { return .none }
                
                state.lastUsedPencil = penType
                return .none

            case .scope(.verseRowAction(
                .element(id: let id, action: .view(.updateVerseFrame(let globalRect))))
            ):
                return updateVerseFrame(
                    state: &state,
                    id: id,
                    globalRect: globalRect
                )
                
            case .scope(.canvasAction(.undoStateChanged(let canUndo, let canRedo))):
                state.headerState.palatteSetting.canUndo = canUndo
                state.headerState.palatteSetting.canRedo = canRedo
                return .none

            case .scope(.headerAction(.palatteAction(.view(.undo)))):
                return .send(.scope(.canvasAction(.undo)))
                
            case .scope(.headerAction(.palatteAction(.view(.redo)))):
                return .send(.scope(.canvasAction(.redo)))
                
            case .view(.tapForHeaderHidden):
                return .send(.scope(.headerAction(.toggleVisibility)))
                
            case .view(.twoFingerDoubleTapForUndo):
                return .send(.scope(.canvasAction(.undo)))
                
            default: return .none
            }
        }
        .forEach(\.verseRowState,
                  action: \.scope.verseRowAction) {
            VerseRowFeature()
        }
    }
    
    
    enum CarveReducerError: Error {
        case fetchSentenceError
        case chapterConvertError
    }
}


extension CarveDetailFeature {
    /// 성경 본문 가져오기
    /// - Parameter chapter: 가져올 성경의 제목과 장
    private func fetchBible(chapter: BibleChapter) throws(CarveReducerError) -> [BibleVerse] {
        let encodingEUCKR = CFStringConvertEncodingToNSStringEncoding(0x0422)
        var sentences: [BibleVerse] = []
        guard let textPath = ResourcesResources.bundle.path(forResource: chapter.title.rawValue,
                                                            ofType: nil)
        else { return sentences}
        do {
            let bible = try String(contentsOfFile: textPath,
                                   encoding: String.Encoding(rawValue: encodingEUCKR))
            sentences = try bible.components(separatedBy: "\r")
                .filter {
                    guard let num = $0.components(separatedBy: ":").first,
                          let first = Int(num) else { throw CarveReducerError.chapterConvertError }
                    return first == chapter.chapter
                }
                .map { sentence in
                    return BibleVerse.init(title: chapter, sentence: sentence)
                }
        } catch {
            throw .fetchSentenceError
        }
        return sentences
    }
    
    
    /// 1. 성경 본문 fetch
    /// 2. sentenceWithDrawingState 및 canvasState 초기화,
    /// 3. Drawing데이터 불러옴
    private func handleFetchSentence(state: inout State) -> Effect<Action> {
        let title = state.headerState.currentTitle
          
        return .run { send in
            do {
                let sentences = try fetchBible(chapter: title)
                try Task.checkCancellation()
                
                await send(.setFetchedSentence(chapter: title, verses: sentences))
            } catch {
                Log.error("Fetch Sentence Error")
            }
        }
        .cancellable(id: CancelID.fetchBible(title: title), cancelInFlight: true)
    }

    /// sentenceSetting 변경을 관찰하고 텍스트 레이아웃 재측정을 요청.
    /// - Side Effect: Shared publisher 구독
    private func observeSentenceSetting(state: State) -> Effect<Action> {
        let sentenceSettingPublisher = state.$sentenceSetting.publisher.removeDuplicates()
        return .run { send in
            for await _ in sentenceSettingPublisher.values {
                await send(.view(.invalidateTextLayoutDebounced))
            }
        }
        .cancellable(id: CancelID.observeSentenceSetting, cancelInFlight: true)
    }
    
    
    /// ScrollView 맨 위로 스크롤
    private func scrollToTop(state: inout State) -> Effect<Action> {
        guard let id = state.verseRowState.first?.id else { return .none }
        withAnimation(.easeInOut(duration: 0.5)) {
            state.proxy?.scrollTo(id, anchor: .bottom)
        }
        return .none
    }
    
    private func scrollToPendingVerseIfPossible(state: inout State) -> Effect<Action> {
        guard let verse = state.pendingScrollVerse,
              let proxy = state.proxy,
              let rowID = state.verseRowState
            .first(where: { $0.sentence.verse == verse.verse })?
            .id
        else { return .none }
        
        withAnimation(.easeInOut(duration: 0.5)) {
            proxy.scrollTo(rowID, anchor: .center)
        }
        
        state.pendingScrollVerse = nil
        return .none
    }
    
    
    /// Sentence 셀에서 전달된 content 좌표를 Canvas 기준 좌표로 사용하고,
    /// 각 절의 rect를 CombinedCanvasFeature에 전달.
    /// - Parameters:
    ///   - id: 각 절의 상태 ID
    ///   - globalRect: 각 절의 Rect (Content 좌표계)
    private func updateVerseFrame(
        state: inout State,
        id: VerseRowFeature.State.ID,
        globalRect: CGRect
    ) -> Effect<Action> {
        guard let index = state.verseRowState.firstIndex(where: { $0.id == id }) else {
            return .none
        }
        let sentenceState = state.verseRowState[index]
        let verse = sentenceState.sentence.verse

        // content 좌표를 그대로 canvas 좌표로 사용
        let localRect = globalRect

        return .send(.scope(.canvasAction(
            .verseFrameUpdated(verse: verse, rect: localRect)
        )))
    }
}
