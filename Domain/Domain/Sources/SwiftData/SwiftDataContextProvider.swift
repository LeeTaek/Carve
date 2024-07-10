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
        context: { PersistentCloudKitContainer.shared.context }
    )
    
    public static let testValue: SwiftDataContextProvider = Self(
        context: { PersistentCloudKitContainer.testConatiner.context }
    )
    
}

extension DependencyValues {
    public var databaseService: SwiftDataContextProvider {
        get { self[SwiftDataContextProvider.self] }
        set { self[SwiftDataContextProvider.self] = newValue}
    }
}

final class PersistentCloudKitContainer: @unchecked Sendable {
    static let shared = PersistentCloudKitContainer(isLive: true)
    static let testConatiner = PersistentCloudKitContainer(isLive: false)
    let container: ModelContainer
    let context: ModelContext
    
    private init(isLive: Bool) {
        let path = isLive ? "Carve.sqlite" : "Carve.test.sqlite"
        do {
            let url = URL.applicationSupportDirectory.appending(path: path)
            let schema = Schema([
                DrawingVO.self
            ])
            let config = ModelConfiguration(url: url)
            container = try ModelContainer(for: schema, configurations: config)
            context = ModelContext(container)
        } catch {
            fatalError("Failed to create SwiftData container")
        }
    }
}
