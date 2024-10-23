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
    public static let shared = PersistentCloudKitContainer(isLive: true)
    public static let testConatiner = PersistentCloudKitContainer(isLive: false)
    public let container: ModelContainer
    
    private init(isLive: Bool) {
        let path = isLive ? "Carve.sqlite" : "Carve.test.sqlite"
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
    }
}
