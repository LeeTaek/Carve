//
//  SwiftDatabaseActor.swift
//  Domain
//
//  Created by 이택성 on 4/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import SwiftData

import Dependencies

public protocol Database {
    associatedtype Item: PersistentModel
    func fetch() async throws -> Item
    func add(item: Item) async throws
    func update(item: Item) async throws
}


@ModelActor
public actor SwiftDatabaseActor {
    public func fetch<T: PersistentModel>() async throws -> [T] {
        let descriptor = FetchDescriptor<T>()
        return try self.modelContext.fetch(descriptor)
    }
    
    public func fetch<T: PersistentModel>(id: PersistentIdentifier) async throws -> T {
        let object: T = self.modelContext.model(for: id) as! T
        return object
    }
    
    public func insert<T: PersistentModel>(_ item: T) async throws {
        return self.modelContext.insert(item)
    }
    
    public func update<T: PersistentModel>(_ id: PersistentIdentifier,
                                           query: @Sendable @escaping (_ oldValue: T) -> Void) async throws {
        let storedItem: T = try await self.fetch(id: id)
        query(storedItem)
    }
    
    public func delete<T: PersistentModel>(_ item: T) async {
        
        return self.modelContext.delete(item)
    }
    
    public func save() async throws {
        try self.modelContext.save()
    }
}

extension SwiftDatabaseActor: DependencyKey {
    public static var liveValue: @Sendable () async throws -> SwiftDatabaseActor = {
        @Dependency(\.databaseService.context) var context
        let container = try context().container
        return SwiftDatabaseActor(modelContainer: container)
    }
    
    public static var testValue: @Sendable () async throws -> SwiftDatabaseActor = {
        @Dependency(\.databaseService.context) var context
        let container = try context().container
        return SwiftDatabaseActor(modelContainer: container)
    }
}


extension DependencyValues {
    public var createSwiftDataActor: @Sendable () async throws -> SwiftDatabaseActor {
        get { self[SwiftDatabaseActor.self] }
        set { self[SwiftDatabaseActor.self] = newValue }
    }
}
