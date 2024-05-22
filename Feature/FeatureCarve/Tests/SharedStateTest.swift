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

    func test_change_shared_state_title() async throws {
        // givn
        @Dependency(\.defaultAppStorage) var userDefaults
        let title = TitleVO(title: .acts, chapter: 2)
        print("path", userDefaults.volatileDomainNames)
        
        // when
        await store.send(.view(.selectChapter(.acts, 2)))
        guard let savedData = userDefaults.data(forKey: "title") else { throw SharedStateError.userDefaultsIsNone }
        let savedTitle = try JSONDecoder().decode(TitleVO.self, from: savedData)
        
        // then
        XCTAssertEqual(store.state.currentTitle, savedTitle)
    }
    
}
