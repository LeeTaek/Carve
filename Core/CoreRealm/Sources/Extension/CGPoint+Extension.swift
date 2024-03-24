//
//  CGPoint+Extension.swift
//  CoreRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import RealmSwift

extension CGPoint: CustomPersistable {
    public typealias PersistedType = PointDTO
    
    public init(persistedValue: PointDTO) {
        self.init(x: persistedValue.x, y: persistedValue.y)
    }
    
    public var persistableValue: PointDTO {
        PointDTO(self)
    }
}
