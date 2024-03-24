//
//  SentencesWithDrawingView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/22/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Common
import CommonUI
import SwiftUI

import ComposableArchitecture

public struct SentencesWithDrawingView: View {
    private let store: StoreOf<SentencesWithDrawingReducer>
    @ObservedObject
    private var viewStore: ViewStore<SentencesWithDrawingReducer.State, SentencesWithDrawingReducer.Action>
    
    public init(store: StoreOf<SentencesWithDrawingReducer>) {
        self.store = store
        self.viewStore = ViewStore(self.store, observe: { $0 })
    }
    
    public var body: some View {
            HStack {
                BibleSentenceView(store: Store(initialState: viewStore.sentenceState) {
                    BibleSentenceReducer()
                })
                .onDescriptionRectSize { rect in
                    let frameHeight = rect.height
                    let numberOfLines = Int(frameHeight / viewStore.sentenceState.lineSpace)
                    viewStore.send(.view(.calculateLineOffsets(numberOfLines, frameHeight)))
                }
                
                Spacer()
                
                DrawingView(store: Store(initialState: viewStore.drawingState) {
                    DrawingReducer()
                })
            }
    }
    
}
