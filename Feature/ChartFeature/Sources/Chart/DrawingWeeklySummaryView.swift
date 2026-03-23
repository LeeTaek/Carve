//
//  DrawingWeeklySummaryView.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import ClientInterfaces
import UIComponents
import CarveToolkit
#if DEBUG
import Domain
#endif

import ComposableArchitecture

@ViewAction(for: DrawingWeeklySummaryFeature.self)
public struct DrawingWeeklySummaryView: View {
    @Bindable public var store: StoreOf<DrawingWeeklySummaryFeature>

    public init(store: StoreOf<DrawingWeeklySummaryFeature>) {
        self.store = store
    }

    public var body: some View {
        LazyVGrid(
            columns: tileColumns,
            alignment: .leading,
            spacing: 16
        ) {
            TileCard(title: "최근 필사 내역") {
                latestDrawingHistoryTile
            }

            TileCard(title: "표시 중인 주 평균") {
                weeklyAverageTile
            }

            TileCard(title: "표시 중인 주 최고 장") {
                topChapterTile
            }

            if !store.adSlotState.isLoading {
                TileCard(title: "스폰서") {
                    sponsorAdTile
                }
                .transition(.opacity)
            }
        }
        .animation(
            .spring(response: 0.35, dampingFraction: 0.9),
            value: !store.adSlotState.isLoading
        )
        .onAppear {
            send(.onAppear)
        }
    }

    /// 화면 폭에 따라서 Grid가 1열/2열/3열로 개행되도록 설정.
    private var tileColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 220, maximum: 420),
                spacing: 12,
                alignment: .topLeading
            )
        ]
    }

    private var latestDrawingHistoryTile: some View {
        return VStack(alignment: .leading, spacing: 6) {
            Text("한 주 동안")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(store.weekTotalCount)절")
                .font(.title3)
                .foregroundStyle(Color.Brand.ink)
                .monospacedDigit()

            Text("최근")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            recentVersesList

            Spacer(minLength: 0)

            Text("필사하셨어요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 최신 필사 절 목록(최신순)
    @ViewBuilder
    private var recentVersesList: some View {
        if store.recentVerses.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.recentVerses.prefix(3)) { item in
                    Button {
                        send(.recentVerseTapped(item))
                    } label: {
                        Text("• \(item.message)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
        }
    }

    private var weeklyAverageTile: some View {
        return VStack(alignment: .leading, spacing: 6) {
            Text("평균")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(store.weekAverageCount)절/일")
                .font(.title3)
                .foregroundStyle(Color.Brand.ink)
                .monospacedDigit()

            Text("최근")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            recentChaptersList
            Spacer(minLength: 0)

            Text("필사하셨어요")
                .font(.caption)
                .foregroundStyle(.secondary)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 최근 필사한 장 목록(최신순)
    @ViewBuilder
    private var recentChaptersList: some View {
        if store.recentChapters.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                let items = Array(store.recentChapters.prefix(3))

                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    Button {
                        send(.recentChapterTapped(item))
                    } label: {
                        Text("• \(item.title.koreanTitle()) \(item.chapter)장")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
        }
    }

    private var topChapterTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이번 주")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(store.weekMaxCount)")
                .font(.title3)
                .foregroundStyle(Color.Brand.ink)
                .lineLimit(2)

            Spacer(minLength: 0)

            Text("(절 수 기준)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sponsorAdTile: some View {
        AdSlotView(
            store: store.scope(
                state: \.adSlotState,
                action: \.adSlot
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
#Preview("DrawingWeeklySummaryView") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let pageStart = calendar.date(byAdding: .day, value: -6, to: today)!

    var state = DrawingWeeklySummaryFeature.State()
    state.scrollPosition = pageStart

    // 30일치 더미 기록(날짜는 startOfDay로 고정)
    state.dailyRecords = (0..<30).map { offset in
        let day = calendar.date(byAdding: .day, value: -offset, to: today)!
        let count = [0, 3, 5, 8, 2, 10, 6][offset % 7]
        return DailyRecord(date: calendar.startOfDay(for: day), count: count)
    }
    .sorted { $0.date < $1.date }

    let romans8 = BibleChapter(title: .romans, chapter: 8)
    let genesis1 = BibleChapter(title: .genesis, chapter: 1)

    let pageDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: pageStart) }
        .map { calendar.startOfDay(for: $0) }

    state.chapterCountsByDay = Dictionary(uniqueKeysWithValues: pageDates.enumerated().map { index, day in
        if index % 2 == 0 {
            return (day, [romans8: 4 + index])
        } else {
            return (day, [genesis1: 2 + index])
        }
    })

    state.recentVerses = [
        RecentVerseItem(
            verse: .init(title: .init(title: .genesis, chapter: 1), verse: 10, sentence: ""),
            updatedAt: today
        ),
        RecentVerseItem(
            verse: .init(title: .init(title: .genesis, chapter: 1), verse: 9, sentence: ""),
            updatedAt: today
        )
    ]

    state.recentChapters = [
        romans8,
        genesis1
    ]

    let store = Store(initialState: state) {
        DrawingWeeklySummaryFeature()
    }

    return DrawingWeeklySummaryView(store: store)
        .padding()
        .background(Color.Brand.background)
}
#endif
