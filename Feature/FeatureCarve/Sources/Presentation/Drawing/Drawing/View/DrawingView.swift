//
//  DrawingView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import ComposableArchitecture
import DomainRealm
import SwiftUI

public struct DrawingView: View {
    private let store: StoreOf<DrawingReducer>
    @ObservedObject
    private var viewStore: ViewStore<DrawingReducer.State, DrawingReducer.ViewAction>
    
    public init(store: StoreOf<DrawingReducer>) {
        self.store = store
        self.viewStore = ViewStore(self.store,
                                   observe: { $0 },
                                   send: { .view($0) })
    }
    
    public var body: some View {
        ZStack {
            underLineView
            canvasView
        }
        .frame(width: UIScreen.main.bounds.width / 2,
               alignment: .topTrailing)
    }
    
    public var canvasView: some View {
        let store = Store(initialState: .initialState) {
            CanvasReducer()
        }
        return CanvasView(store: store)
    }
    
    public var underLineView: some View {
        VStack(spacing: 0) {
            ForEach(0..<viewStore.underLineCount, id: \.self) { lineIndex in
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .frame(height: viewStore.underlineOffset[lineIndex]) // 밑줄 높이
            }
        }
        .padding(.horizontal, 20)
    }
    
  
    
    struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.maxY))
            return path
        }
    }
    
}

#Preview {
    let store = Store(initialState: DrawingReducer.State(title: .init(title: .genesis,
                                                                      chapter: 1),
                                                         section: 1)) {
        DrawingReducer()
    }
    return DrawingView(store: store)
}
