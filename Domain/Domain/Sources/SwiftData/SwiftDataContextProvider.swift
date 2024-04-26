//
//  SwiftDatabase.swift
//  Domain
//
//  Created by 이택성 on 4/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import SwiftData

import Dependencies

public struct SwiftDataContextProvider: Sendable {
    public var context: () throws -> ModelContext
}

extension SwiftDataContextProvider: DependencyKey {
    public static let liveValue: SwiftDataContextProvider = Self(
    context: { appContext }
    )
    
    public static let testValue: SwiftDataContextProvider = Self(
        context: { testAppContext }
    )
    
}

extension DependencyValues {
    public var databaseService: SwiftDataContextProvider {
        get { self[SwiftDataContextProvider.self] }
        set { self[SwiftDataContextProvider.self] = newValue}
    }
}

private let appContext: ModelContext = {
    do {
        let url = URL.applicationSupportDirectory.appending(path: "Carve.sqlite")
        let schema = Schema([
            TitleVO.self
        ])
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    } catch {
        fatalError("Failed to create SwiftData container")
    }
}()

private let testAppContext: ModelContext = {
    do {
        let url = URL.applicationSupportDirectory.appending(path: "Carve.test.sqlite")
        let schema = Schema([
            TitleVO.self
        ])
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    } catch {
        fatalError("Failed to create SwiftData container")
    }
}()


