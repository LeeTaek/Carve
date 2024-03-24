//
//  DependencyContainor.swift
//  Carve
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Common
import CoreRealm
import DomainRealm

import Dependencies

public final class DependencyContainor {
    public let realmRepository: RealmInterface

    public init(realmRepository: RealmInterface) {
        self.realmRepository = realmRepository
    }
}

extension DependencyContainor: DependencyKey {
    public static var liveValue: @Sendable () async throws -> DependencyContainor = {
        do {
            let repository = try await RealmRepository()
            return .init(realmRepository: repository)
        } catch {
            Log.error("dependency error", error)
            throw error
        }
    }
}
