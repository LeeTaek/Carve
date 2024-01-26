//
//  CarveView.swift
//  AppManifests
//
//  Created by 이택성 on 1/22/24.
//

import SwiftUI
import ComposableArchitecture

public struct CarveMainView: View {
    public let store: StoreOf<CarveReducer>

    public init(store: StoreOf<CarveReducer>) {
        self.store = store
    }

    public var body: some View {
        WithViewStore(self.store, observe: { $0 }) { viewStore in
            VStack(alignment: .leading) {
                Text("\(viewStore.text)")
            }
        }
    }
}
