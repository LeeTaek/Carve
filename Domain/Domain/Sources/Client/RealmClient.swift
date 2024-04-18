//
//  RealmClient.swift
//  DomainRealm
//
//  Created by 이택성 on 4/18/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import Dependencies
import RealmSwift


public class RealmClient {
    let realm: Realm
    
    public init() {
        self.realm = try! Realm()
    }
    
    public func get<T: Object>(key: RealmStorageKeyType) -> T? {
        let object: T? = realm.object(ofType: T.self, forPrimaryKey: key.name)
        return object
    }
    
    public func set<T: Object>(_ value: T, forKey: RealmStorageKeyType) {
        try! realm.write {
            if self.get(key: forKey) != nil {
                realm.add(value, update: .modified)
            } else {
                realm.add(value)
            }
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
            let object: TitleVO = (get(key: .bibleTitle)) ?? .init(title: .genesis, chapter: 1)
            return object
        }
        set { set(newValue, forKey: .bibleTitle) }
    }
}

extension RealmClient: DependencyKey {
    public static var liveValue: RealmClient = RealmClient()
}

extension DependencyValues {
    public var realmClient: RealmClient {
        get { self[RealmClient.self] }
        set { self[RealmClient.self] = newValue }
    }
}
