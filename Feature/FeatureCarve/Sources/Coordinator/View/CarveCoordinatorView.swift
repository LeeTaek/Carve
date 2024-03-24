//
//  CarveCoordinatorView.swift
//  Feature
//
//  Created by 이택성 on 1/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import ComposableArchitecture
import TCACoordinators

public struct CarveCoordinatorView: View {
    let store: StoreOf<CarveCoordinator>

    public init(store: StoreOf<CarveCoordinator>) {
        self.store = store
    }

    public var body: some View {
        TCARouter(store) { screen in
            SwitchStore(screen) { screen in
                switch screen {
                case .carve:
                    CaseLet(
                        /CarveScreen.State.carve,
                         action: CarveScreen.Action.carve,
                         then: CarveView.init
                    )
                }
            }
        }
    }
}
