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
import ClientInterfaces

import ComposableArchitecture

@Reducer
public struct DrawingWeeklySummaryFeature {
    @ObservableState
    public struct State {
        /// 광고 상태
        public var adSlotState: SponsorAdSlotFeature.State = .init(
            placement: .chartCard
        )
        /// 주간 차트 기준 startOfDay
        public var scrollPosition: Date = Calendar.current.startOfDay(for: Date())
        /// 전체 일별 필사 기록
        public var dailyRecords: [DailyRecord] = []
        /// 날짜(startOfDay) 기준 장별 카운트
        public var chapterCountsByDay: [Date: [BibleChapter: Int]] = [:]
        /// 표시용 최근 항목들
        public var recentVerses: [RecentVerseItem] = []
        public var recentChapters: [BibleChapter] = []
        
        public init() {}
        
        // MARK: - 계산 프로퍼티
        /// 차트가 현재 보여주는 주의 시작일(=scrollPosition startOfDay)
        private var pageStartDate: Date {
            Calendar.current.startOfDay(for: scrollPosition)
        }
        /// 주간 범위
        private var pageEndExclusive: Date {
            Calendar.current.date(byAdding: .day, value: 7, to: pageStartDate)!
        }
        /// 주간 범위 계산
        private var currentWeekRecords: [DailyRecord] {
            let cal = Calendar.current
            return dailyRecords.filter { record in
                let day = cal.startOfDay(for: record.date)
                return (pageStartDate <= day) && (day < pageEndExclusive)
            }
        }
        /// 이번 주 총 합
        public var weekTotalCount: Int {
            Log.debug(currentWeekRecords)
            return currentWeekRecords.reduce(0) { $0 + $1.count }
        }
        /// 이번 주 평균(절/일) — 7일 고정
        public var weekAverageCount: Int {
            Int(round(Double(weekTotalCount) / 7.0))
        }
        /// 이번 주 최대 필사량(하루 max)
        public var weekMaxCount: Int {
            currentWeekRecords.map(\.count).max() ?? 0
        }
        /// 이번 주 7일 날짜 목록 (startOfDay 기준)
        private var currentWeekDates: [Date] {
            let cal = Calendar.current
            return (0..<7)
                .compactMap { cal.date(byAdding: .day, value: $0, to: pageStartDate) }
                .map { cal.startOfDay(for: $0) }
        }
        /// 이번 주 최고 장(장 + 절 수)
        public var topChapter: (chapter: BibleChapter, count: Int)? {
            var merged: [BibleChapter: Int] = [:]
            
            for day in currentWeekDates {
                let counts = chapterCountsByDay[day, default: [:]]
                for (chapter, count) in counts {
                    merged[chapter, default: 0] += count
                }
            }
            
            guard let best = merged.max(by: { $0.value < $1.value }) else { return nil }
            return (best.key, best.value)
        }
    }
    
    public enum Action: ViewAction {
        case adSlot(SponsorAdSlotFeature.Action)
        case view(View)
        /// 네비게이션 트리거
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
        Scope(state: \.adSlotState, action: \ .adSlot) {
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
