//
//  RealmUsecase.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

public class RealmUsecase {
    let repository: RealmInterface

    public init(repository: RealmInterface) {
        self.repository = repository
    }

    public func setSubscriptions() async throws {
        try await repository.setSubscriptions()
    }

    public func clearSubscriptions() async throws {
        try await repository.clearSubscriptions()
    }

}
