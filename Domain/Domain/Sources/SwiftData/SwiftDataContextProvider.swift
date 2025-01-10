//
//  SwiftDatabase.swift
//  Domain
//
//  Created by 이택성 on 4/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import SwiftData
import CloudKit

import Dependencies

public final class PersistentCloudKitContainer {
    private enum ContainerType {
        case live
        case test
        case preview
    }
    public static let shared = PersistentCloudKitContainer(type: .live)
    public static let test = PersistentCloudKitContainer(type: .test)
    public static let preview = PersistentCloudKitContainer(type: .preview)
    public let container: ModelContainer
    
    private init(type: ContainerType) {
        switch type {
        case .live, .test:
            let path = if type == .live { "Carve.sqlite" } else { "Carve.test.sqlite" }
            do {
                let url = URL.applicationSupportDirectory.appending(path: path)
                let schema = Schema([
                    DrawingVO.self
                ])
                let config = ModelConfiguration(
                    url: url,
                    cloudKitDatabase: .private("iCloud.Carve.SwiftData.iCloud")
                )
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create SwiftData container")
            }
        case .preview:
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(for: Schema([DrawingVO.self]), configurations: config)
            } catch {
                fatalError("Failed to create SwiftData container on Preview")
            }
        }
    }
}
