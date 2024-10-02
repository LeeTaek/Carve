//
//  SwiftDatabaseActor.swift
//  Domain
//
//  Created by 이택성 on 4/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import SwiftData
import Core

import Dependencies

public protocol Database {
    associatedtype Item: PersistentModel
    func fetch() async throws -> Item
    func add(item: Item) async throws
    func update(item: Item) async throws
}

@ModelActor
public actor SwiftDatabaseActor {
    public enum SwiftDatabaseActorError: Error {
        case storedDataIsNone
    }
    
    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T> = .init()) throws -> [T] {
        let fetched: [T] = try self.modelContext.fetch(descriptor)
        Log.debug("fetched data's count", fetched.count)
        return fetched
    }
    
    public func fetch<T: PersistentModel>(id: PersistentIdentifier) -> T? {
        let object: T? = self.modelContext.model(for: id) as? T
        return object
    }
    
    public func insert<T: PersistentModel>(_ item: T) throws {
        self.modelContext.insert(item)
        try self.modelContext.save()
    }
    
    public func update<T: PersistentModel>(_ id: PersistentIdentifier,
                                           query: @Sendable @escaping (_ oldValue: T) async -> Void) async throws {
        if let storedItem: T = self.fetch(id: id) {
            await query(storedItem)
            try self.modelContext.save()
        } else {
            throw SwiftDatabaseActorError.storedDataIsNone
        }
    }
    
    public func delete<T: PersistentModel>(_ item: T) throws {
        self.modelContext.delete(item)
        try self.modelContext.save()
    }
    
    public func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        try self.modelContext.delete(model: T.self)
    }
    
    public func databaseIsEmpty<T: PersistentModel>(_ type: T.Type) throws -> Bool {
        let objects: [T] = try self.fetch()
        return objects.isEmpty
    }
}


extension SwiftDatabaseActor: DependencyKey {
    public static var liveValue: SwiftDatabaseActor = {
        let container = PersistentCloudKitContainer.shared.container
        return SwiftDatabaseActor(modelContainer: container)
    }()
    
    public static var testValue: SwiftDatabaseActor = {
        let container = PersistentCloudKitContainer.testConatiner.container
        return SwiftDatabaseActor(modelContainer: container)
    }()
}

extension DependencyValues {
    public var createSwiftDataActor: SwiftDatabaseActor {
        get { self[SwiftDatabaseActor.self] }
        set { self[SwiftDatabaseActor.self] = newValue }
    }
}
