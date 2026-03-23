//
//  DrawingWeeklySummaryView.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI
import UIComponents
import CarveToolkit

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
        VStack(alignment: .leading, spacing: 6) {
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

    @ViewBuilder
    private var recentVersesList: some View {
        if !store.recentVerses.isEmpty {
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
        VStack(alignment: .leading, spacing: 6) {
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

    @ViewBuilder
    private var recentChaptersList: some View {
        if !store.recentChapters.isEmpty {
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

            if let topChapter = store.topChapter {
                Button {
                    send(.topChapterTapped)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(topChapter.chapter.title.koreanTitle()) \(topChapter.chapter.chapter)장")
                            .font(.title3)
                            .foregroundStyle(Color.Brand.ink)
                            .lineLimit(2)
                        Text("\(topChapter.count)절")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("기록 없음")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

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
