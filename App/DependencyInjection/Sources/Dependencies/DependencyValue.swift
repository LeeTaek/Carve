//
//  DependencyValue.swift
//  Carve
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Dependencies

extension DependencyValues {
    public var realmRepository: DependencyContainor {
        get { self[DependencyContainor.self] }
        set { self[DependencyContainor.self] = newValue }
    }
}
