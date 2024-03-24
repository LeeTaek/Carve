//
//  PersistableColor.swift
//  CoreRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import RealmSwift

public class ColorDTO: EmbeddedObject {
    @Persisted var red: Double
    @Persisted var green: Double
    @Persisted var blue: Double
    @Persisted var opacity: Double
    
    public convenience init(color: Color) {
        self.init()
        if let components = color.cgColor?.components {
            if components.count >= 3 {
                red = components[0]
                green = components[1]
                blue = components[2]
            }
            if components.count >= 4 {
                opacity = components[3]
            }
        }
    }
}
