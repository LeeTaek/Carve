//
//  SentenceDrewHistoryListView.swift
//  FeatureCarve
//
//  Created by 이택성 on 7/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

@ViewAction(for: SentenceDrewHistoryListReducer.self)
public struct SentenceDrewHistoryListView: View {
    @Bindable public var store: StoreOf<SentenceDrewHistoryListReducer>
    
    public init(store: StoreOf<SentenceDrewHistoryListReducer>) {
        self.store = store
    }
    
    public var body: some View {
        content
    }
    
    public var content: some View {
        Text("Hello, World!")
    }
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { SentenceDrewHistoryListReducer() }
    )
    SentenceDrewHistoryListView(store: store)
}
