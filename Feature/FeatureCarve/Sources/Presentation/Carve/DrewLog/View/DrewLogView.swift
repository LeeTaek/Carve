//
//  DrewLogReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 1/9/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Core
import Charts
import Domain
import SwiftUI

import ComposableArchitecture

public struct DrewLogView: View {
    @Bindable private var store: StoreOf<DrewLogReducer>
    @State private var isAnimating: Bool = false
    @State private var textAnimating: Bool = false

    public init(store: StoreOf<DrewLogReducer>) {
        self.store = store
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            title
            Spacer()
            if store.isLoading {
                loadingView
                Spacer()
            } else {
                content
            }
        }
        .onAppear {
            store.send(.inner(.fetchChartData))
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
    
    private var content: some View {
        GeometryReader { geometry in
            List {
                Section {
                    chart
                        .frame(
                            width: (geometry.size.width/9) * 8,
                            height: geometry.size.height/4,
                            alignment: .center
                        )
                } header: {
                    chartTitle
                }
                Section {
                    carvingTrackerChart
                } header: {
                    carvingTrackerChartTitle
                }
            }
        }
        .transition(.opacity)
    }
    
    private var title: some View {
        Button(action: { store.send(.view(.dismiss)) }) {
            Text("필사 기록")
                .navigationTitleStyle()
        }
        .padding(.horizontal)
    }
    
    private var chartTitle: some View {
        HStack {
            if store.chartData.isEmpty {
                Text("지난 한 주 필사 내역이 없어요.")
                    .sublineStyle(size: 18, opacity: 0.7)
            } else {
                Text("지난 한 주")
                    .sublineStyle(size: 18, opacity: 0.7)
                Text("\(store.totalSection)")
                    .sublineStyle(size: 25)
                
                Text("절의 말씀을 새겼네요.")
                    .sublineStyle(size: 18, opacity: 0.7)
            }
        }
    }
    
    private var chart: some View {
        Chart(store.chartData) { entry in
            BarMark(
                x: .value("Date", entry.date, unit: .day),
                y: .value("Count", isAnimating ? entry.count : 0),
                width: 50
            )
            .annotation(position: .top, alignment: .center) {
                Text("\(entry.count)절")
                    .fixedSize()
                    .sublineStyle(size: 12, opacity: textAnimating ? 0.7: 0)
                    .animation(.easeInOut(duration: 1.0), value: textAnimating)
                
            }
            .cornerRadius(10)
            .foregroundStyle(by: .value("Date", entry.date))
        }
        .chartYScale(domain: 0...store.maxY)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.month().day(), centered: true)
                AxisGridLine()
            }
        }
        .padding()
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeInOut(duration: 1.0)) {
                self.isAnimating = true
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            withAnimation(.easeInOut(duration: 10.0)) {
                self.textAnimating = true
            }
        }
    }
    
    private var loadingView: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            VStack {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding()
                Text("필사 데이터를 불러오는 중입니다... ")
                    .sublineStyle(size: 18, opacity: 0.7)
                    .padding()
            }
        }
        .transition(.opacity)
    }
    
    
    private var carvingTrackerChartTitle: some View {
        Text("필사 현황")
            .sublineStyle(size: 18, opacity: 0.7)
    }
    private var carvingTrackerChart: some View {
        ForEach(BibleTitle.allCases, id: \.self) { book in
            VStack(alignment: .leading, spacing: 8) {
                Text(book.koreanTitle())
                    .sublineStyle(size: 16)
                    .padding([.horizontal, .top])
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 10),
                    spacing: 8
                ) {
                    ForEach(1...book.lastChapter, id: \.self) { chapter in
                        Text("\(chapter)")
                            .sublineStyle(size: 16, opacity: 0.7)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(Color(uiColor: .systemGray6))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { DrewLogReducer() },
        withDependencies: {
            $0.drawingData = .previewValue
        }
    )
    return DrewLogView(store: store)
}
