//
//  RealmTest.swift
//  DomainTest
//
//  Created by 이택성 on 4/19/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import XCTest
@testable import Domain

import RealmSwift

final class RealmTest: XCTestCase {
    
    var testRealm: Realm!
    var realmClient: RealmClient!
    
    override func setUpWithError() throws {
        self.testRealm = try Realm(configuration: Realm.Configuration(inMemoryIdentifier: "testRealm"))
        self.realmClient = RealmClient(realm: testRealm)
    }

    override func tearDownWithError() throws {
        try testRealm.write {
            testRealm.deleteAll()
        }
    }

    func test_set_realm() throws {
        //given
        let title: TitleVO = .init(title: .acts, chapter: 1)
        
        //when
        realmClient.set(title, forKey: .bibleTitle) { object in
            object.id = title.id
            object.title = title.title
            object.chapter = title.chapter
        }
        
        //then
        let storedObject = testRealm.object(ofType: TitleVO.self, forPrimaryKey: RealmStorageKeyType.bibleTitle)
        XCTAssertEqual(storedObject, title)
    }
    
    func test_get_realm() throws {
        //given
        let title: TitleVO = .init(title: .acts, chapter: 1)
        realmClient.set(title, forKey: .bibleTitle) { object in
            object.id = title.id
            object.title = title.title
            object.chapter = title.chapter
        }
        
        //when
        guard let storedObject: TitleVO = realmClient.get(key: .bibleTitle) else {
            XCTFail("storedObject is Nil")
            return
        }
        
        // then
        XCTAssertEqual(storedObject, title)
    }
    
    func test_remove_realm() throws {
        //given
        let title: TitleVO = .init(title: .acts, chapter: 1)
        realmClient.currentTitle = title

        // when
        realmClient.delete(title, forKey: .bibleTitle)
        
        // then
        let storedObject = testRealm.object(ofType: TitleVO.self, forPrimaryKey: RealmStorageKeyType.bibleTitle)
        XCTAssertNil(storedObject)
    }
    
    
    func test_realm_currentTitle() throws {
        //given
        let changedTitle: TitleVO = .init(title: .acts, chapter: 1)
        
        // when
        realmClient.currentTitle = changedTitle
        
        // then
        XCTAssertEqual(realmClient.currentTitle.key, changedTitle.key)
        XCTAssertEqual(realmClient.currentTitle.id, changedTitle.id)
        XCTAssertEqual(realmClient.currentTitle.title, changedTitle.title)
        XCTAssertEqual(realmClient.currentTitle.chapter, changedTitle.chapter)
        XCTAssertEqual(realmClient.currentTitle, changedTitle)
    }
    
    func test_realm_change_currentTitle() throws {
        // when
        let title: TitleVO = .init(title: .acts, chapter: 1)
        let changedTitle: TitleVO = .initialState
        
        // when
        realmClient.currentTitle = title
        XCTAssertEqual(realmClient.currentTitle, title)
        
        // then
        realmClient.currentTitle = changedTitle
        XCTAssertEqual(realmClient.currentTitle, changedTitle)
    }
    
    

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
