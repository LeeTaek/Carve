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
            // 저장된 drawing은 local 좌표라고 가정하지만,
            // padding/변환 과정에서 bounds.minX/minY가 0이 아닐 수 있어 프리뷰에서 잘릴 수 있다.
            // 항상 (0,0) 기준으로 정규화해서 렌더링한다.
            let originalBounds = pkDrawing.bounds
            let normalizedDrawing = pkDrawing.transformed(
                using: CGAffineTransform(translationX: -originalBounds.minX, y: -originalBounds.minY)
            )
            let normalizedBounds = normalizedDrawing.bounds

            // List 셀에서 0 height로 압축되는 것을 방지
            let previewWidth = max(44, normalizedBounds.width)
            let previewHeight = max(44, normalizedBounds.height)

            Button {
                send(.selectDrawing(drawing))
            } label: {
                DrawingPreview(drawing: normalizedDrawing)
                    .frame(width: previewWidth, height: previewHeight)
                    .frame(maxWidth: .infinity, alignment: .center)
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
        reducer: { VerseDrawingHistoryFeature() }
    )
    VerseDrawingHistoryView(store: store)
}
