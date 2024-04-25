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

public struct TitleDatabase {
    public var fetch: @Sendable () throws -> TitleVO
    public var add: @Sendable (TitleVO) throws -> Void
    public var update: @Sendable (TitleVO) throws -> Void
    
    public enum TitleError: Error {
        case fetch
        case update
    }
}

extension TitleDatabase: DependencyKey {
    public static let liveValue: TitleDatabase = Self(
        fetch: {
            let descriptor = FetchDescriptor<TitleVO>()
            do {
                @Dependency(\.databaseService.context) var context
                let titleContext = try context()
                guard let title = try titleContext.fetch(descriptor).first else { return .init(title: .genesis, chapter: 1) }
                return title
            } catch {
                @Dependency(\.databaseService.context) var context
                let titleContext = try context()
                titleContext.insert(TitleVO.init(title: .genesis, chapter: 1))
                return .init(title: .genesis, chapter: 1)
            }
        },
        add: { title in
            do {
                @Dependency(\.databaseService.context) var context
                let titleContext = try context()
                titleContext.insert(title)
            } catch {
                Log.debug("SwiftData add error", title)
            }
        },
        update: { title in
            do {
                @Dependency(\.databaseService.context) var context
                let titleContext = try context()
                let descriptor = FetchDescriptor<TitleVO>()
                guard let storedTitle = try titleContext.fetch(descriptor).first else {
                    titleContext.insert(title)
                    return
                }
                storedTitle.title = title.title
                storedTitle.chapter = title.chapter
            } catch {
                Log.debug("SwiftData update error", title)
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
