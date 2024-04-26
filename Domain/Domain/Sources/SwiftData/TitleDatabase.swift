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

public struct TitleDatabase: Sendable {
    public var fetch: @Sendable () async throws -> TitleVO
    public var add: @Sendable (TitleVO) async throws -> Void
    public var update: @Sendable (TitleVO) async throws -> Void
    
    public enum TitleError: Error {
        case fetch
        case update
    }
}

extension TitleDatabase: DependencyKey {
    public static let liveValue: TitleDatabase = Self(
        fetch: {
            @Dependency(\.createSwiftDataActor) var createActor
            let fetchTask = Task.detached { () -> TitleVO in
                let actor = try await createActor()
                if let storedTitle: TitleVO = try await actor.fetch().first {
                    return storedTitle
                } else {
                    try await actor.insert(TitleVO.initialState)
                    return TitleVO.init(title: .genesis, chapter: 1)
                }
            }
            do {
                let title = try await fetchTask.result.get()
                return title
            } catch {
                return .initialState
            }
        },
        add: { title in
            @Dependency(\.createSwiftDataActor) var createActor
            Task.detached {
                let actor = try await createActor()
                try await actor.insert(title)
                try await actor.save()
            }
        },
        update: { title in
            @Dependency(\.createSwiftDataActor) var createActor
            Task.detached {
                let actor = try await createActor()
                if let storedTitle: TitleVO = try await actor.fetch().first {
                    try await actor.update(storedTitle.id) { (oldValue: TitleVO) in
                        oldValue.title = title.title
                        oldValue.chapter = title.chapter
                    }
                } else {
                    try await actor.insert(title)
                }
                try await actor.save()
            }
        }
    )
}

extension DependencyValues {
    public var titleData: TitleDatabase {
        get { self[TitleDatabase.self] }
        set { self[TitleDatabase.self] = newValue }
    }
}
