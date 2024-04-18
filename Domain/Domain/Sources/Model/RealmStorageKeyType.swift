//
//  RealmStorageKeyType.swift
//  DomainRealm
//
//  Created by 이택성 on 4/17/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

import ComposableArchitecture

protocol StorageKeyType {
    var name: String { get }
}


public enum RealmStorageKeyType: String, StorageKeyType {
    case bibleTitle
    
    
    public var name: String {
        return "RealmStorage_\(self.rawValue)"
    }
}
