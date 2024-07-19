//
//  LisenceView.swift
//  FeatureSettings
//
//  Created by 이택성 on 7/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture

public struct LisenceView: View {
    private var store: StoreOf<LisenceReducer>
    
    public init(store: StoreOf<LisenceReducer>) {
        self.store = store
    }
    
    public var body: some View {
        Text("Lisence")
    }
}