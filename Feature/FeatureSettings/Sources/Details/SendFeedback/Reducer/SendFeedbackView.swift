//
//  SendFeedbackView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/24/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct SendFeedbackView: View {
    private var store: StoreOf<SendFeedbackReducer>
    
    public init(store: StoreOf<SendFeedbackReducer>) {
        self.store = store
    }
    
    public var body: some View {
        Text("SendFeedback")
    }
}
