//
//  SwiftDataTest.swift
//  DomainTest
//
//  Created by 이택성 on 4/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

@testable import Domain
import XCTest
import SwiftData

import Dependencies

final class SwiftDataTest: XCTestCase {
    var modelContext: ModelContext!
    var titleDataBase: TitleDatabase!

    override func setUpWithError() throws {
        self.modelContext = {
            @Dependency(\.databaseService) var databaseService
            guard let modelContext = try? databaseService.context() else {
                fatalError("Could not find modelcontext")
            }
            return modelContext
        }()
        self.titleDataBase = TitleDatabase()
    }

    override func tearDown() async throws {
        try self.modelContext.delete(model: TitleVO.self)
        self.modelContext = nil
        self.titleDataBase = nil
    }

    func test_fetch_title() async throws {
        // given
        let title = TitleVO.initialState
        
        // when
        let initTitle = try await titleDataBase.fetch()
        
        // then
        XCTAssertEqual(initTitle, title)
    }
    
    func test_add_title() async throws {
        // given
        let title = TitleVO.init(title: .acts, chapter: 1)
        
        // when
        try await titleDataBase.add(item: title)
        
        // then
        let storedTitle = try await titleDataBase.fetch()
        XCTAssertEqual(storedTitle, title)
    }
    
    func test_update_title() async throws {
        // given
        let title = TitleVO.init(title: .acts, chapter: 1)
        let givenTitle = TitleVO.init(title: .colossians, chapter: 1)
        
        // when
        try await titleDataBase.add(item: title)
        try await titleDataBase.update(item: givenTitle)
        
        // then
        let storedTitle = try await titleDataBase.fetch()
        XCTAssertEqual(storedTitle, givenTitle)
    }

}
