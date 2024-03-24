//
//  PersistablePoint.swift
//  CoreRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import RealmSwift

public class PointDTO: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var x: Double
    @Persisted var y: Double
    
    public convenience init(_ point: CGPoint) {
        self.init()
        self.x = point.x
        self.y = point.y
    }
}
