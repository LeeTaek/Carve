//
//  CGFloat+Extension.swift
//  CoreRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import RealmSwift

extension CGFloat: CustomPersistable {
    public typealias PersistedType = Double
    
    public init(persistedValue: Double) {
        self.init(persistedValue)
    }
    public var persistableValue: Double {
        Double(self)
    }
    
}
