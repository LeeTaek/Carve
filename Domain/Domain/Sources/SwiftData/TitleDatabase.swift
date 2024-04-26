//
//  TitleDatabase.swift
//  Domain
//
//  Created by 이택성 on 4/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Foundation
import SwiftData

import Dependencies

public struct TitleDatabase: Sendable, Database {
    public func fetch() async throws -> TitleVO {
        @Dependency(\.createSwiftDataActor) var createActor
        let actor = try await createActor()
        if let storedTitle: TitleVO = try await actor.fetch().first {
            return storedTitle
        } else {
            try await actor.insert(TitleVO.initialState)
            return TitleVO.init(title: .genesis, chapter: 1)
        }
    }
    
    public func add(item: TitleVO) async throws {
        @Dependency(\.createSwiftDataActor) var createActor
        let actor = try await createActor()
        try await actor.insert(item)
        try await actor.save()
        
    }
    
    public func update(item: TitleVO) async throws {
        @Dependency(\.createSwiftDataActor) var createActor
        let actor = try await createActor()
        if let storedTitle: TitleVO = try await actor.fetch().first {
            try await actor.update(storedTitle.id) { (oldValue: TitleVO) in
                oldValue.title = item.title
                oldValue.chapter = item.chapter
            }
        } else {
            try await actor.insert(item)
        }
        try await actor.save()
    }
    
    public enum TitleError: Error {
        case fetch
        case update
    }
}

extension TitleDatabase: DependencyKey {
    public static let liveValue: TitleDatabase = Self()
    public static let testValue: TitleDatabase = Self()
}

extension DependencyValues {
    public var titleData: TitleDatabase {
        get { self[TitleDatabase.self] }
        set { self[TitleDatabase.self] = newValue }
    }
}
