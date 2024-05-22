//
//  CarveCoordinatorView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import TCACoordinators

public struct CarveCoordinatorView: View {
    private var store: StoreOf<CarveCoordinator>
    
    public init(store: StoreOf<CarveCoordinator>) {
        self.store = store
    }
    
    public var body: some View {
        TCARouter(store.scope(state: \.routes, action: \.router)) { screen in
            switch screen.case {
            case let .carve(store):
                CarveView(store: store)
            }
        }
    }
}
