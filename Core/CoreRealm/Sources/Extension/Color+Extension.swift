//
//  Color+Extension.swift
//  CoreRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import RealmSwift

extension Color: CustomPersistable {
    public typealias PersistedType = ColorDTO

    public init(persistedValue: ColorDTO) {
        self.init(
            .sRGB,
            red: persistedValue.red,
            green: persistedValue.green,
            blue: persistedValue.blue,
            opacity: persistedValue.opacity
        )
    }
    
    public var persistableValue: ColorDTO {
        ColorDTO(color: self)
    }
}
