//
//  DailyRecordChartFeature.swift
//  ChartFeature
//
//  Created by 이택성 on 12/19/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI
import CarveToolkit

import ComposableArchitecture

struct ChartPage: Equatable {
    let start: Date
    let end: Date
    let entries: [DailyRecord]
    let xDomain: ClosedRange<Date>
}

@Reducer
public struct DailyRecordChartFeature {
    /// 한 페이지에 표시할 날짜 수(주간 단위)
    static let pageDays: Int = 7
    private let visiblePageIndex = 1
    
    public enum PageMove: Equatable { case prev, stay, next }
    private enum CancelID { case paging, yScale }
    
    @ObservableState
    public struct State {
        static let initialState = Self()
        /// 차트에 표시할 데이터
        var records: [DailyRecord] = []
        /// 스크롤 가능한 날짜 하한선 (오늘 - 30일)
        var lowerBoundDate: Date = .distantPast
        /// 현재 페이지의 leading 날짜. 처음 진입시 오늘
        var scrollPosition: Date = Calendar.current.startOfDay(for: Date())
        /// 차트에서 선택된 날짜
        var selectedDate: Date?
        /// 페이지 레이아웃 계산에 필요한 넓이
        var pageWidth: CGFloat = 0
        /// 드래그 오프셋(가운데 페이지 기준)
        /// - prev: +pageWidth, stay: 0, next: -pageWidth
        var dragX: CGFloat = 0
        /// 스크롤 여부,
        /// 부모 스크롤(List) 잠그는 용도로 사용
        var isScrolling: Bool = false
        /// 화면에 렌더링할 3페이지(prev/current/next) 캐시
        var pages: [ChartPage] = []
        /// y축 도메인
        var yScale: ClosedRange<Double> = 0...1
        
        init(
            records: [DailyRecord] = [],
            lowerBoundDate: Date = .distantPast,
            scrollPosition: Date = Calendar.current.startOfDay(for: Date()),
            selectedDate: Date? = nil
        ) {
            self.records = records
            self.lowerBoundDate = lowerBoundDate
            self.scrollPosition = scrollPosition
            self.selectedDate = selectedDate
        }
     }
        
    public enum Action: ViewAction, BindableAction {
        case binding(BindingAction<State>)
        case view(View)
        /// page/yScale 을 현재 상태 기준으로 재구성
        /// force가 true면 anchor가 같아도 재빌드
        case rebuild(force: Bool)
        /// 드래그 종료 후 어느 방향으로 페이지를 이동할지 결정
        case commitMove(PageMove)
        /// commitMove 끝난 후 실제 anchor 변경 및 pages 교체
        case finishMove(PageMove)
        /// yScale 범위가 줄어들 경우 애니메이션 지연을 위해 분리한 액션
        case applyYScale(ClosedRange<Double>)
        
        public enum View {
            /// 최초 렌더링 시 pageWidth 주입
            case onAppear(width: CGFloat)
            /// 회전, 리사이즈 등으로 width가 바뀔 때
            case widthChanged(CGFloat)
            /// 드래그 진행 시 translationX 업데이트
            case dragChanged(translationX: CGFloat)
            /// 드래그 종료시 PageMove 결정
            case dragEnded(translationX: CGFloat)
        }
    }
    
    public var body: some Reducer<State, Action> {
        BindingReducer()
            .onChange(of: \.scrollPosition) { _, _ in
                Reduce { state, _ in
                    rebuildPagesIfNeeded(&state)
                    return .none
                }
            }
            .onChange(of: \.records) { _, _ in
                Reduce { state, _ in
                    rebuildPagesIfNeeded(&state, force: true)
                    return .none
                }
            }
        
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
                
            case .rebuild(let force):
                rebuildPagesIfNeeded(&state, force: force)
                return .none
                
            case .commitMove(let move):
                return handleCommitMove(&state, move: move)
                
            case .finishMove(let move):
                return handleFinishMove(&state, move: move)
                
            case .applyYScale(let range):
                withAnimation(.easeInOut(duration: 0.34)) {
                    state.yScale = range
                }
                return .none
                
            case .view(.onAppear(let width)):
                state.pageWidth = width
                return .send(.rebuild(force: true))
                
            case .view(.widthChanged(let width)):
                state.pageWidth = width
                return .none
                
            case .view(.dragChanged(let translationX)):
                state.isScrolling = true
                state.selectedDate = nil

                let upperBoundDate = Calendar.current.startOfDay(for: Date())
                let maxOverscroll = min(120, state.pageWidth * 0.22)

                // 경계에 막히면 rubber-band(저항) 적용
                if translationX > 0, !canMove(.prev, state: state, upperBoundDate: upperBoundDate) {
                    state.dragX = rubberBand(translationX, maxOverscroll: maxOverscroll)
                } else if translationX < 0, !canMove(.next, state: state, upperBoundDate: upperBoundDate) {
                    state.dragX = rubberBand(translationX, maxOverscroll: maxOverscroll)
                } else {
                    // 이동 가능한 범위에서도 과도한 드래그는 살짝 저항을 줌(최대 1.15페이지 정도)
                    let limit = state.pageWidth
                    let maxExtra = state.pageWidth * 0.15
                    let absT = abs(translationX)
                    if absT <= limit {
                        state.dragX = translationX
                    } else {
                        let extra = absT - limit
                        let dampedExtra = maxExtra * (extra / (extra + maxExtra))
                        let signed = (translationX >= 0 ? 1.0 : -1.0)
                        state.dragX = CGFloat(signed) * (limit + dampedExtra)
                    }
                }

                return .none
                
            case .view(.dragEnded(let translationX)):
                let threshold: CGFloat = max(60, state.pageWidth * 0.15)
                let upperBoundDate = Calendar.current.startOfDay(for: Date())
                
                let move: PageMove = {
                    if translationX > threshold {
                        return canMove(.prev, state: state, upperBoundDate: upperBoundDate) ? .prev : .stay
                    } else if translationX < -threshold {
                        return canMove(.next, state: state, upperBoundDate: upperBoundDate) ? .next : .stay
                    } else {
                         return .stay
                    }
                }()
                
                return .send(.commitMove(move))
            }
        }
    }
    
}

extension DailyRecordChartFeature {
    /// 현재 `scrollPosition`(anchor) 기준으로 3페이지(prev/current/next)를 재구성.
    /// - Parameters:
    ///   - force: true면 anchor가 동일해도 강제로 재계산.
    /// - 초기 구성은 애니메이션 없이 즉시 `pages`/`yScale` 반영.
    private func rebuildPagesIfNeeded(_ state: inout State, force: Bool = false) {
        let aligned = state.scrollPosition.alignToDay()
        
        if force || state.pages.isEmpty || state.pages[safe: visiblePageIndex]?.start != aligned {
            let upperBoundDate = Calendar.current.startOfDay(for: Date())
            state.pages = make3Pages(
                anchorStart: aligned,
                records: state.records,
                lowerBoundDate: state.lowerBoundDate,
                upperBoundDate: upperBoundDate
            )
            
            // 초기 구성은 즉시 반영(애니메이션 없이)
            if let scale = targetYScale(for: state.pages) {
                state.yScale = scale
            }
        }
    }
    
    /// 사용자가 드래그로 페이지를 넘기려 할 때 해당 방향으로 이동 가능한지 판단.
    /// - Returns: 이동 가능하면 true
    private func canMove(_ move: PageMove, state: State, upperBoundDate: Date) -> Bool {
        let start = state.pages[safe: visiblePageIndex]?.start ?? state.scrollPosition.alignToDay()
        let minStart = clampAnchorStart(
            state.lowerBoundDate,
            lowerBoundDate: state.lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        let maxStart = clampAnchorStart(
            upperBoundDate.addDays(-(Self.pageDays - 1)),
            lowerBoundDate: state.lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        
        switch move {
        case .prev: return start.addDays(-Self.pageDays) >= minStart
        case .stay: return true
        case .next: return start.addDays(Self.pageDays) <= maxStart
        }
    }
    
    /// anchorStart를 중심으로 prev/current/next 총 3개의 ChartPage를 생성.
    private func make3Pages(
        anchorStart: Date,
        records: [DailyRecord],
        lowerBoundDate: Date,
        upperBoundDate: Date
    ) -> [ChartPage] {
        let anchor = clampAnchorStart(
            anchorStart.alignToDay(),
            lowerBoundDate: lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        let prevStart = clampAnchorStart(
            anchor.addDays(-Self.pageDays),
            lowerBoundDate: lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        let nextStart = clampAnchorStart(
            anchor.addDays(Self.pageDays),
            lowerBoundDate: lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        
        return [
            makePage(start: prevStart, records: records),
            makePage(start: anchor, records: records),
            makePage(start: nextStart, records: records)
        ]
    }
    
    
    /// start(포함)부터 7일 구간의 ChartPage를 생성.
    /// - Parameters:
    ///   - start: 페이지 시작일(포함, startOfDay로 정렬)
    ///   - records: 전체 DailyRecord 중 해당 범위에 속하는 것만 필터링
    /// - Returns: (start ... endExclusive) xDomain을 갖는 ChartPage
    private func makePage(start: Date, records: [DailyRecord]) -> ChartPage {
        let start = start.alignToDay()
        let end = start.addDays(Self.pageDays - 1)
        let endExclusive = start.addDays(Self.pageDays)      // 다음날 00:00
        
        let entries = records
            .filter {
                let day = $0.date.alignToDay()      // 시간 제거
                return day >= start && day < endExclusive
            }
            .sorted { $0.date < $1.date }
        
        return ChartPage(
            start: start,
            end: end,
            entries: entries,
            xDomain: start...endExclusive
        )
    }
    
    
    /// pages 전체(prev/current/next)의 최대 count를 기준으로 y축 도메인을 계산.
    /// - Parameter pages: 화면에 렌더링할 3페이지
    /// - Returns: 데이터가 없으면 nil, 있으면 0...max+headroom(상단 여백을 위해 + max의 40%)
    func targetYScale(for pages: [ChartPage]) -> ClosedRange<Double>? {
        let allCounts = pages.flatMap { $0.entries.map(\.count) }
        guard let maxInt = allCounts.max(), maxInt > 0 else { return nil }
        
        let top = max(1, Double(maxInt))
        let headroom = max(1, ceil(top * 0.4))   // 상단 여유 2/5(=0.4)
        return 0...(top + headroom)
    }
    
    
    /// anchorStart(페이지 시작일)를 lowerBound~upperBound 범위에 맞춰 clamp.
    private func clampAnchorStart(
        _ start: Date,
        lowerBoundDate: Date,
        upperBoundDate: Date
    ) -> Date {
        let cal = Calendar.current
        let minStart = cal.startOfDay(for: lowerBoundDate)
        let maxStart = cal.date(byAdding: .day, value: -(Self.pageDays - 1), to: upperBoundDate) ?? upperBoundDate
        return min(max(start.alignToDay(), minStart), maxStart.alignToDay())
    }
    
    /// pull-to-refresh처럼, 더 당길수록 저항이 커지도록 translation을 감쇠.
    /// - Parameters:
    ///   - translationX: 원본 드래그 translation
    ///   - maxOverscroll: 최대 오버스크롤 허용량(이 이상은 거의 움직이지 않음)
    /// - Returns: 저항이 적용된 translation
    private func rubberBand(_ translationX: CGFloat, maxOverscroll: CGFloat) -> CGFloat {
        guard maxOverscroll > 0 else { return 0 }
        let trans = abs(translationX)
        let damped = maxOverscroll * (trans / (trans + maxOverscroll))
        return translationX >= 0 ? damped : -damped
    }
    
    /// 드래그 종료 후 결정된 PageMove에 맞춰 페이저 오프셋을 애니메이션으로 이동
    /// `.cancellable(id: .paging, cancelInFlight: true)`로 연속 스와이프시 작업 취소.
    private func handleCommitMove(_ state: inout State, move: PageMove) -> Effect<Action> {
        // 이동이 없는 경우(또는 경계에 막힌 경우) 즉시 bounce back
        guard move != .stay else {
            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                state.dragX = 0
            }
            state.isScrolling = false
            return .none
        }

        let targetDelta: CGFloat = {
            switch move {
            case .prev: return state.pageWidth
            case .stay: return 0
            case .next: return -state.pageWidth
            }
        }()

        withAnimation(.easeOut(duration: 0.22)) {
            state.dragX = targetDelta
        }

        return .run { send in
            try? await Task.sleep(nanoseconds: 240_000_000)
            await send(.finishMove(move))
        }
        .cancellable(id: CancelID.paging, cancelInFlight: true)
    }

    /// commitMove 애니메이션이 끝난 뒤 실제 anchor 변경 + pages/yScale 교체.
    /// - Note:
    ///   - 축 확장: yScale을 먼저 키우고 pages를 교체
    ///   - 축 축소: pages를 먼저 교체하고 짧게 홀드 후 yScale을 줄임
    private func handleFinishMove(_ state: inout State, move: PageMove) -> Effect<Action> {
        let upperBoundDate = Calendar.current.startOfDay(for: Date())
        
        let currentStart = state.pages[safe: visiblePageIndex]?.start ?? state.scrollPosition.alignToDay()
        let newAnchor: Date = {
            switch move {
            case .prev: return currentStart.addDays(-Self.pageDays)
            case .stay: return currentStart
            case .next: return currentStart.addDays(Self.pageDays)
            }
        }()
        
        state.scrollPosition = clampAnchorStart(
            newAnchor,
            lowerBoundDate: state.lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        
        // 3페이지 재구성
        let newPages = make3Pages(
            anchorStart: state.scrollPosition,
            records: state.records,
            lowerBoundDate: state.lowerBoundDate,
            upperBoundDate: upperBoundDate
        )
        
        let target = targetYScale(for: newPages)
        
        if let target {
            let currentUpper = state.yScale.upperBound
            let targetUpper = target.upperBound
            
            if targetUpper > currentUpper {
                // 확장: 먼저 축을 늘리고 페이지를 교체
                withAnimation(.easeInOut(duration: 0.3)) { state.yScale = target }
                state.pages = newPages
                
            } else if targetUpper < currentUpper {
                // 축소: 먼저 페이지 교체 -> 짧게 홀드 -> 축소
                state.pages = newPages
                state.yScale = 0...max(currentUpper, targetUpper)
                
                // 항상 가운데로 복귀 / 스크롤 종료는 선반영
                state.dragX = 0
                state.isScrolling = false
                
                return .run { send in
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    await send(.applyYScale(target))
                }
                .cancellable(id: CancelID.yScale, cancelInFlight: true)
                
            } else {
                // 축 변화 없음
                state.pages = newPages
                state.yScale = target
            }
            
        } else {
            // 데이터가 비어 있으면 축 변경 생략
            state.pages = newPages
        }
        
        // 항상 가운데로 복귀
        state.dragX = 0
        state.isScrolling = false
        return .none
    }
}
