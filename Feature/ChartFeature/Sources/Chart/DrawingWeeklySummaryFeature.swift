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
