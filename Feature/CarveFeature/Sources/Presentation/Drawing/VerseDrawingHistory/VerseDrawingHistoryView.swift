//
//  SentenceDrewHistoryListView.swift
//  FeatureCarve
//
//  Created by 이택성 on 7/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Domain
import Resources
import SwiftUI
import PencilKit

import ComposableArchitecture
import UIComponents

@ViewAction(for: VerseDrawingHistoryFeature.self)
public struct VerseDrawingHistoryView: View {
    @Bindable public var store: StoreOf<VerseDrawingHistoryFeature>
    
    public init(store: StoreOf<VerseDrawingHistoryFeature>) {
        self.store = store
    }
    
    public var body: some View {
        content
    }
    
    private var content: some View {
        VStack(alignment: .leading) {
            Text("\(store.title.title.koreanTitle()) \(store.title.chapter)장 \(store.verse)절 필사 기록")
                .font(Font(ResourcesFontFamily.NanumGothic.bold.font(size: 25)))
                .foregroundStyle(CarveColor.ink)
                .padding()
            
            if store.drawings.isEmpty {
                VStack {
                    Spacer()
                    Text("필사 내역이 없습니다.")
                        .font(Font(ResourcesFontFamily.NanumGothic.bold.font(size: 20)))
                        .foregroundStyle(CarveColor.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
            } else {
                drewList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            send(.fetchDrawings)
        }
    }
    
    private var drewList: some View {
        List {
            ForEach(store.drawings) { drawing in
                Section {
                    drawingPreview(of: drawing)
                        .padding()
                } header: {
                    updatedDate(date: drawing.updateDate)
                }
            }
        }
    }
    
    @ViewBuilder
    private func drawingPreview(of drawing: BibleDrawing) -> some View {
        if let drawingData = drawing.lineData,
           let pkDrawing = try? PKDrawing(data: drawingData) {
            let bounds = pkDrawing.bounds
            let height = bounds.height
            let aspectRatio = bounds.height > 0 ? bounds.width / bounds.height : 1.0
            let width = height * aspectRatio
            
            Button {
                send(.selectDrawing(drawing))
            } label: {
                DrawingPreview(drawing: pkDrawing)
                    .frame(width: width, height: height)
                    .padding()
                    // 필기는 종이 위에 보여 준다 — 다크 목록 행 위에 검정 잉크가 묻히지 않게(결정 8-1 안 1).
                    .background(CarveColor.Paper.background, in: RoundedRectangle(cornerRadius: CarveRadius.control))
            }
        } else {
            Text("불러올 수 없는 필사 데이터입니다.")
                .padding(.vertical)
        }
    }
    
    private func updatedDate(date: Date?) -> some View {
        if let date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy년 MM월 dd일 HH:mm"
            return Text("필사 날짜: \(formatter.string(from: date))")
        } else {
            return Text("날짜를 확인할 수 없습니다.")
        }
    }
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { VerseDrawingHistoryFeature() }
    )
    VerseDrawingHistoryView(store: store)
}
