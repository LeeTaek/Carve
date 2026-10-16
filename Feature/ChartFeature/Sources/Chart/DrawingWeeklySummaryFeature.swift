//
//  DrawingWeeklySummaryFeature.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import Domain
import CarveToolkit
import UIComponents

import ComposableArchitecture

@Reducer
public struct DrawingWeeklySummaryFeature {
    @ObservableState
    public struct State {
        public var adSlotState: SponsorAdSlotFeature.State = .init(placement: .chartCard)
        public var scrollPosition: Date = Calendar.current.startOfDay(for: Date())
        public var dailyRecords: [DailyRecord] = []
        /// 날짜(자정)별 · 장(번역본 포함)별 필사 수 — 모든 필사책을 합산한다(2.2 결정 10).
        public var chapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
        /// 날짜(자정)별 · 장(번역본 포함)별로 그날 그 장을 마지막으로 쓴 필사책 — `chapterCountsByDay` 와 같은 행 · 같은 키로 만든다.
        /// 가장 많이 쓴 장을 열 필사책을 고른다(`topChapterPage`).
        public var chapterNotebooksByDay: [Date: [BibleChapter: NotebookID]] = [:]
        /// 최근에 고친 절 — 행마다 하나, 그 행의 필사책 · 번역본 장을 든다.
        public var recentVerses: [RecentVerseItem] = []
        /// 최근에 쓴 장 — 필사책을 합산해 장(번역본 포함)마다 한 줄이고, 그 장을 마지막으로 쓴 필사책의 장이다.
        public var recentChapters: [NotebookChapter] = []
        
        public init() {}
        
        private var pageStartDate: Date {
            Calendar.current.startOfDay(for: scrollPosition)
        }
        
        private var pageEndExclusive: Date {
            Calendar.current.date(byAdding: .day, value: 7, to: pageStartDate)!
        }
        
        private var currentWeekRecords: [DailyRecord] {
            let cal = Calendar.current
            return dailyRecords.filter { record in
                let day = cal.startOfDay(for: record.date)
                return (pageStartDate <= day) && (day < pageEndExclusive)
            }
        }
        
        public var weekTotalCount: Int {
            currentWeekRecords.reduce(0) { $0 + $1.count }
        }
        
        public var weekAverageCount: Int {
            Int(round(Double(weekTotalCount) / 7.0))
        }

        /// 역할: 주간 합계를 7일로 나눈 값을 소수점 한 자리로 적는다(「1.7」).
        /// 입력 · 출력: 로케일(뷰는 환경 locale) → 그 로케일의 수 서식으로 적은 평균.
        /// 부작용: 없음.
        public func weekAverageText(locale: Locale) -> String {
            (Double(weekTotalCount) / 7.0).formatted(.number.precision(.fractionLength(1)).locale(locale))
        }
        
        public var weekMaxCount: Int {
            currentWeekRecords.map(\.count).max() ?? 0
        }
        
        private var currentWeekDates: [Date] {
            let cal = Calendar.current
            return (0..<7)
                .compactMap { cal.date(byAdding: .day, value: $0, to: pageStartDate) }
                .map { cal.startOfDay(for: $0) }
        }
        
        /// 성경 순서(창세기 → 요한계시록) 비교용 인덱스 캐시.
        /// `BibleTitle.allCases`의 나열 순서가 곧 성경 정경 순서이므로 그대로 사용한다.
        private static let bibleTitleOrder: [BibleTitle: Int] = Dictionary(
            uniqueKeysWithValues: BibleTitle.allCases.enumerated().map { ($0.element, $0.offset) }
        )

        /// 번역본 순서 비교용 인덱스 캐시 — `Translation.allCases` 의 나열 순서(개역개정 · KJV · BSB)다.
        private static let translationOrder: [Translation: Int] = Dictionary(
            uniqueKeysWithValues: Translation.allCases.enumerated().map { ($0.element, $0.offset) }
        )

        /// `topChapter` 선정용 정렬 키.
        ///
        /// 합계가 같을 때 `Dictionary`의 순회 순서에 의존하면 프로세스마다 달라지는
        /// 해시 시드 때문에 결과가 비결정적이 된다. 그래서 아래와 같은 전순서(total order)를 만들어
        /// 동점이어도 항상 같은 권/장이 뽑히도록 한다.
        ///
        /// 1. 합계 내림차순 (가장 많이 필사한 권이 먼저)
        /// 2. 성경 순서 오름차순 (동점이면 창세기 쪽이 먼저)
        /// 3. 장 번호 오름차순 (같은 권이면 앞 장이 먼저)
        /// 4. 번역본 순서 오름차순 (같은 장을 여러 번역본으로 같은 수만큼 썼으면 `Translation.allCases` 앞쪽이 먼저)
        private struct TopChapterRank: Comparable {
            /// 합계. 내림차순 비교를 위해 부호를 뒤집어 보관한다.
            let negatedCount: Int
            /// `BibleTitle.allCases` 기준 성경 순서 인덱스.
            let titleOrder: Int
            /// 장 번호.
            let chapter: Int
            /// `Translation.allCases` 기준 번역본 순서 인덱스.
            let translationOrder: Int

            init(chapter: BibleChapter, count: Int) {
                self.negatedCount = -count
                self.titleOrder = State.bibleTitleOrder[chapter.title] ?? Int.max
                self.chapter = chapter.chapter
                self.translationOrder = State.translationOrder[chapter.translation] ?? Int.max
            }

            static func < (lhs: Self, rhs: Self) -> Bool {
                if lhs.negatedCount != rhs.negatedCount { return lhs.negatedCount < rhs.negatedCount }
                if lhs.titleOrder != rhs.titleOrder { return lhs.titleOrder < rhs.titleOrder }
                if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
                return lhs.translationOrder < rhs.translationOrder
            }
        }

        /// 이번 주 가장 많이 쓴 장(번역본 포함) — 모든 필사책을 합산하고(2.2 결정 10), 같은 권 · 장도 번역본이 다르면 따로 센다.
        public var topChapter: (chapter: BibleChapter, count: Int)? {
            var merged: [BibleChapter: Int] = [:]

            for day in currentWeekDates {
                let counts = chapterCountsByDay[day, default: [:]]
                for (chapter, count) in counts {
                    merged[chapter, default: 0] += count
                }
            }

            let best = merged.min { lhs, rhs in
                TopChapterRank(chapter: lhs.key, count: lhs.value)
                < TopChapterRank(chapter: rhs.key, count: rhs.value)
            }
            guard let best else { return nil }
            return (best.key, best.value)
        }

        /// 이번 주 가장 많이 쓴 장을 여는 곳 — 필사책을 합산해 고른 장을, 이번 주에 그 장을 마지막으로 쓴 필사책으로 연다(「이어서 쓰기」).
        /// 그 장을 쓴 필사책을 모르면(`chapterNotebooksByDay` 에 없으면) nil 이다 — 기본 필사책으로 바꿔 열지 않는다.
        public var topChapterPage: NotebookChapter? {
            guard let chapter = topChapter?.chapter else { return nil }
            // 보이는 주의 마지막 날부터 거슬러 — 그 장이 든 가장 늦은 날의 필사책이 마지막으로 쓴 필사책이다.
            for day in currentWeekDates.reversed() {
                if let notebook = chapterNotebooksByDay[day]?[chapter] {
                    return NotebookChapter(notebook: notebook, chapter: chapter)
                }
            }
            return nil
        }
    }
    
    public enum Action: ViewAction {
        case adSlot(SponsorAdSlotFeature.Action)
        case view(View)
        /// 최근 절을 골랐다 — 코디네이터가 차트를 닫고 그 필사책 · 번역본의 장에서 그 절을 연다(2.2 결정 10).
        case openVerse(NotebookChapter, verse: Int)
        /// 최근 장 · 가장 많이 쓴 장을 골랐다 — 코디네이터가 차트를 닫고 그 필사책 · 번역본의 장을 연다.
        case openChapter(NotebookChapter)
        
        public enum View {
            case onAppear
            /// 「최근」 의 절을 눌렀다.
            case recentVerseTapped(RecentVerseItem)
            /// 「최근 장」 의 장을 눌렀다 — 그 장을 마지막으로 쓴 필사책의 장이다.
            case recentChapterTapped(NotebookChapter)
            /// 가장 많이 쓴 장 · 「이어서 쓰기」 를 눌렀다.
            case topChapterTapped
        }
    }
    
    public var body: some Reducer<State, Action> {
        Scope(state: \.adSlotState, action: \.adSlot) {
            SponsorAdSlotFeature()
        }

        Reduce { state, action in
            switch action {
            case .view(.onAppear):
                return .send(.adSlot(.startLoad))
                
            case let .view(.recentVerseTapped(item)):
                // 그 항목의 필사책 · 번역본 절로 연다 — 지금 필사 중인 필사책 · 번역본으로 바꾸지 않는다.
                return .send(.openVerse(item.page, verse: item.verse.verse))

            case let .view(.recentChapterTapped(page)):
                // 그 장을 마지막으로 쓴 필사책 · 번역본의 장으로 연다 — 지금 필사책으로 바꾸지 않는다(2.2 결정 10).
                return .send(.openChapter(page))

            case .view(.topChapterTapped):
                // 필사책을 합산해 고른 장을 이번 주에 마지막으로 쓴 필사책으로 연다. 필사책을 모르면 아무 일도 하지 않는다.
                guard let page = state.topChapterPage else { return .none }
                return .send(.openChapter(page))
                
            default:
                return .none
            }
        }
    }
}
