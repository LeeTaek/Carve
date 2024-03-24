//
//  DrawingDTO.swift
//  CoreRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftUI

import RealmSwift

public class DrawingDTO: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) public var id: ObjectId
    @Persisted var author: String
    @Persisted var name: String
    @Persisted var lines: RealmSwift.List<LineDTO> = .init()
    @Persisted var isWrite: Bool = false
    @Persisted var bible: BibleDTO
    
    public convenience init(author: String,
                            name: String,
                            bible: BibleDTO
    ) {
        self.init()
        self.author = author
        self.name = name
        self.bible = bible
    }
    
    public func clean() {
        lines = RealmSwift.List<LineDTO>()
    }
}
