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

import ComposableArchitecture

@Reducer
public struct DrawingWeeklySummaryFeature {
    @ObservableState
    public struct State {
        public var adSlotState: SponsorAdSlotFeature.State = .init(placement: .chartCard)
        public var scrollPosition: Date = Calendar.current.startOfDay(for: Date())
        public var dailyRecords: [DailyRecord] = []
        public var chapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
        public var recentVerses: [RecentVerseItem] = []
        public var recentChapters: [BibleChapter] = []
        
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

        /// `topChapter` 선정용 정렬 키.
        ///
        /// 합계가 같을 때 `Dictionary`의 순회 순서에 의존하면 프로세스마다 달라지는
        /// 해시 시드 때문에 결과가 비결정적이 된다. 그래서 아래와 같은 전순서(total order)를 만들어
        /// 동점이어도 항상 같은 권/장이 뽑히도록 한다.
        ///
        /// 1. 합계 내림차순 (가장 많이 필사한 권이 먼저)
        /// 2. 성경 순서 오름차순 (동점이면 창세기 쪽이 먼저)
        /// 3. 장 번호 오름차순 (같은 권이면 앞 장이 먼저)
        private struct TopChapterRank: Comparable {
            /// 합계. 내림차순 비교를 위해 부호를 뒤집어 보관한다.
            let negatedCount: Int
            /// `BibleTitle.allCases` 기준 성경 순서 인덱스.
            let titleOrder: Int
            /// 장 번호.
            let chapter: Int

            init(chapter: BibleChapter, count: Int) {
                self.negatedCount = -count
                self.titleOrder = State.bibleTitleOrder[chapter.title] ?? Int.max
                self.chapter = chapter.chapter
            }

            static func < (lhs: Self, rhs: Self) -> Bool {
                if lhs.negatedCount != rhs.negatedCount { return lhs.negatedCount < rhs.negatedCount }
                if lhs.titleOrder != rhs.titleOrder { return lhs.titleOrder < rhs.titleOrder }
                return lhs.chapter < rhs.chapter
            }
        }

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
    }
    
    public enum Action: ViewAction {
        case adSlot(SponsorAdSlotFeature.Action)
        case view(View)
        case openVerse(BibleVerse)
        case openChapter(BibleChapter)
        
        public enum View {
            case onAppear
            case recentVerseTapped(RecentVerseItem)
            case recentChapterTapped(BibleChapter)
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
                return .send(.openVerse(item.verse))

            case let .view(.recentChapterTapped(chapter)):
                return .send(.openChapter(chapter))

            case .view(.topChapterTapped):
                guard let chapter = state.topChapter?.chapter else { return .none }
                return .send(.openChapter(chapter))
                
            default:
                return .none
            }
        }
    }
}
