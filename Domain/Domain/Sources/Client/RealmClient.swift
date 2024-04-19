//
//  RealmClient.swift
//  DomainRealm
//
//  Created by 이택성 on 4/18/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import SwiftUI

import Dependencies
import RealmSwift


public class RealmClient {
    let realm: Realm
    
    public init(realm: Realm) {
        self.realm = realm
    }

    public func get<T: Object>(key: RealmStorageKeyType, id: String = "") -> T? {
        let object: T? = realm.object(ofType: T.self, forPrimaryKey: key)
        return object
    }
    
    public func set<T: Object>(_ value: T, 
                               forKey: RealmStorageKeyType,
                               id: String = "",
                               query: @escaping ((T) -> Void) = { _ in }) {
        do {
            try realm.write {
                if let object: T = self.get(key: forKey) {
                    query(object)
                } else {
                    realm.add(value, update: .modified)
                }
            }
        } catch {
            Log.debug("Realm set error:", value)
        }
    }
    
    public func delete<T: Object>(_ value: T, forKey: RealmStorageKeyType) {
        do {
            try realm.write {
                if let object: T = realm.object(ofType: T.self, forPrimaryKey: forKey) {
                    realm.delete(object)
                }
            }
        } catch {
            Log.debug("Realm delete error:", value)
        }
    }
    
//    @MainActor
//    public func setSubscriptions() async throws {
//        let subscriptions = realm.subscriptions
//        try await subscriptions.update {
//            subscriptions.append(
//                QuerySubscription<DrawingVO>(name: "completed-tasks") {
//                    $0.isWrite == true
//                }
//            )
//        }
//    }
//    
//    @MainActor
//    public func clearSubscriptions() async throws {
//        let subscriptions = realm.subscriptions
//        guard let foundSubscriptions = subscriptions.first(named: "completed-tasks") else { return }
//        try await subscriptions.update {
//            subscriptions.remove(foundSubscriptions)
//        }
//    }
//    
    
    //    @MainActor
    //    public func updateSubscription(lines: RealmSwift.List<LineDTO>) async throws {
    //        let subscriptions = realm.subscriptions
    //        try await subscriptions.update {
    //            if let foundSubscription = subscriptions.first(ofType: DrawingDTO.self,
    //                                                           where: {
    //                $0.isWrite == true
    //            }) {
    //                foundSubscription.updateQuery(toType: DrawingDTO.self, where: {
    //                    $0.lines == lines
    //                })
    //            }
    //        }
    //    }
    //}
}


public extension RealmClient {
    var currentTitle: TitleVO {
        get { 
            if let object: TitleVO = self.get(key: .bibleTitle) {
                return object
            } else {
                let initialState = TitleVO.initialState
                self.set(initialState, forKey: .bibleTitle) { title in
                    title.id = initialState.id
                    title.title = initialState.title
                    title.chapter = initialState.chapter
                }
                return initialState
            }
        }
        set {
            self.delete(newValue, forKey: .bibleTitle)
            self.set(newValue, forKey: .bibleTitle) { title in
                title.id = newValue.id
                title.title = newValue.title
                title.chapter = newValue.chapter
            }
        }
    }
}

extension RealmClient: DependencyKey {
    public static var liveValue: RealmClient = RealmClient(realm: try! Realm())
}

extension DependencyValues {
    public var realmClient: RealmClient {
        get { self[RealmClient.self] }
        set { self[RealmClient.self] = newValue }
    }
}
