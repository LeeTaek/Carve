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

@ViewAction(for: SentenceDrewHistoryListFeature.self)
public struct SentenceDrewHistoryListView: View {
    @Bindable public var store: StoreOf<SentenceDrewHistoryListFeature>
    
    public init(store: StoreOf<SentenceDrewHistoryListFeature>) {
        self.store = store
    }
    
    public var body: some View {
        content
    }
    
    private var content: some View {
        VStack(alignment: .leading) {
            Text("\(store.title.title.koreanTitle()) \(store.title.chapter)장 \(store.verse)절 필사 기록")
                .font(Font(ResourcesFontFamily.NanumGothic.bold.font(size: 25)))
                .foregroundStyle(.black.opacity(0.7))
                .padding()
            
            if store.drawings.isEmpty {
                VStack {
                    Spacer()
                    Text("필사 내역이 없습니다.")
                        .font(Font(ResourcesFontFamily.NanumGothic.bold.font(size: 20)))
                        .foregroundStyle(.black.opacity(0.7))
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
        reducer: { SentenceDrewHistoryListFeature() }
    )
    SentenceDrewHistoryListView(store: store)
}
