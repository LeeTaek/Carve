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
    public var context: @Sendable () throws -> ModelContext
}

extension SwiftDataContextProvider: DependencyKey {
    public static let liveValue: SwiftDataContextProvider = Self(
    context: { appContext(isLive: true) }
    )
    
    public static let testValue: SwiftDataContextProvider = Self(
        context: { appContext(isLive: false) }
    )
    
}

extension DependencyValues {
    public var databaseService: SwiftDataContextProvider {
        get { self[SwiftDataContextProvider.self] }
        set { self[SwiftDataContextProvider.self] = newValue}
    }
}

private func appContext(isLive: Bool) -> ModelContext {
    let path = isLive ? "Carve.sqlite" : "Carve.test.sqlite"
    do {
        let url = URL.applicationSupportDirectory.appending(path: path)
        let schema = Schema([
            DrawingVO.self
        ])
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    } catch {
        fatalError("Failed to create SwiftData container")
    }
}
