//
//  SharedStateTest.swift
//  FeatureCarveTest
//
//  Created by 이택성 on 5/14/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import XCTest
@testable import FeatureCarve
@testable import Domain

import ComposableArchitecture

final class SharedStateTest: XCTestCase {
    var store: TestStore<CarveReducer.State, CarveReducer.Action>!
    enum SharedStateError: Error {
        case userDefaultsIsNone
    }

    override func setUpWithError() throws {
        self.store = TestStore(initialState: .initialState) {
            CarveReducer()
        }
        self.store.exhaustivity = .off
    }

    override func tearDownWithError() throws {
        self.store = nil
    }

    
}
