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

public struct SwiftDatabase {
    public var context: () throws -> ModelContext
}

extension SwiftDatabase: DependencyKey {
    public static let liveValue: SwiftDatabase = Self(
    context: { appContext }
    )
}

extension DependencyValues {
    public var databaseService: SwiftDatabase {
        get { self[SwiftDatabase.self] }
        set { self[SwiftDatabase.self] = newValue}
    }
}

fileprivate let appContext: ModelContext = {
    do {
        let url = URL.applicationSupportDirectory.appending(path: "Carve.sqlite")
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(for: TitleVO.self, configurations: config)
        return ModelContext(container)
    } catch {
        fatalError("Failed to create SwiftData container")
    }
}()
