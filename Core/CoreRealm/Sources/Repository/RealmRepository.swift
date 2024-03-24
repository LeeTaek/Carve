//
//  RealmRepository.swift
//  CoreRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Common
import DomainRealm
import SwiftUI

import RealmSwift

public class RealmRepository: RealmInterface {
    let realm: Realm

    public init() async throws {
        self.realm = try await Realm()
    }

    @MainActor
    public func setSubscriptions() async throws {
        let subscriptions = realm.subscriptions
        try await subscriptions.update {
            subscriptions.append(
                QuerySubscription<DrawingDTO>(name: "completed-tasks") {
                    $0.isWrite == true
                }
            )
        }
    }
        
    @MainActor
    public func clearSubscriptions() async throws {
        let subscriptions = realm.subscriptions
        guard let foundSubscriptions = subscriptions.first(named: "completed-tasks") else { return }
        try await subscriptions.update {
            subscriptions.remove(foundSubscriptions)
        }
    }
    
    
    @MainActor
    public func updateSubscription(lines: RealmSwift.List<LineDTO>) async throws {
        let subscriptions = realm.subscriptions
        try await subscriptions.update {
            if let foundSubscription = subscriptions.first(ofType: DrawingDTO.self,
                                                           where: {
                $0.isWrite == true
            }) {
                foundSubscription.updateQuery(toType: DrawingDTO.self, where: {
                    $0.lines == lines
                })
            }
        }
    }
    
}
