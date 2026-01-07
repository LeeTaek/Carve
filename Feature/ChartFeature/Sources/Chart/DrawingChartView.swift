//
//  DrawingChartView.swift
//  ChartFeature
//
//  Created by 이택성 on 8/1/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Charts
import SwiftUI
import CarveToolkit
#if DEBUG
import Domain
import PencilKit
#endif

import ComposableArchitecture

@ViewAction(for: DrawingChartFeature.self)
public struct DrawingChartView: View {
    @Bindable public var store: StoreOf<DrawingChartFeature>

    public init(store: StoreOf<DrawingChartFeature>) {
        self.store = store
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // 상단: 차트 카드(가로 전체)
                CardSection(title: "주간 필사량") {
                    DailyRecordChartView(
                        store: store.scope(
                            state: \.dailyRecordChart,
                            action: \.dailyRecordChart
                        )
                    )
                }

                // 하단: 타일 3개 (가로 여유에 따라 3열/2열/1열로 자동 개행)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    TileCard(title: "최근 필사 내역") {
                        latestDrawingHistoryTile
                    }

                    TileCard(title: "이번 주 평균") {
                        weeklyAverageTile
                    }

                    TileCard(title: "이번 주 최고 장") {
                        topChapterTile
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        // 차트 드래그 중에는 바깥 스크롤을 잠가서 gesture 충돌을 줄임
        .scrollDisabled(store.dailyRecordChart.isScrolling)
        .background(Color.Brand.background)
        .task {
#if DEBUG
            // Xcode 프리뷰에서는 fetchData 안 날림
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                send(.fetchData)
            }
#else
            send(.fetchData)
#endif
        }
    }
    

    private var latestDrawingHistoryTile: some View {
        return VStack(alignment: .leading, spacing: 6) {
            Text("한 주 동안")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(store.currentWeekTotalCount)절")
                .font(.title3)
                .foregroundStyle(Color.Brand.ink)
                .monospacedDigit()

            Spacer(minLength: 0)

            Text("필사하셨어요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var weeklyAverageTile: some View {
        return VStack(alignment: .leading, spacing: 6) {
            Text("평균")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(store.currentWeekAverage)절/일")
                .font(.title3)
                .foregroundStyle(Color.Brand.ink)
                .monospacedDigit()

            Spacer(minLength: 0)

            Text("(최근 7일)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var topChapterTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이번 주")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(store.currentWeekTopChapterText)
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
}


#Preview {
    @Previewable @State var store = Store(initialState: .previewState) {
        DrawingChartFeature()
    } withDependencies: { dependency in
        dependency.drawingData = .previewValue
    }
    
    DrawingChartView(store: store)
}


/// 제목 + 카드 콘텐츠
private struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.Brand.ink)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white)
                .sectionCardShadow()
        }
    }
}

/// 하나의 정사각형 타일 카드
private struct TileCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.Brand.ink)

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white)
        .sectionCardShadow()
        // 타일은 가로 폭을 유지하면서 height를 width와 동일하게.
        .aspectRatio(1, contentMode: .fit)
    }
}
