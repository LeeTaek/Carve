//
//  SwiftDatabaseActor.swift
//  Domain
//
//  Created by 이택성 on 4/26/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import SwiftData
import CarveToolkit

import Dependencies

/// SwiftData ModelContext를 감싸는 Actor입니다.
/// SwiftData에 대한 CURD 제공하며, Actor를 통해 동시성 환경에서 안정성 확보.
@ModelActor
public actor SwiftDatabaseActor {
    public enum SwiftDatabaseActorError: Error {
        /// 주어진 ID에 해당하는 데이터가 존재하지 않을 때 발생하는 에러
        case storedDataIsNone
    }
    
    /// 주어진 FetchDescriptor를 사용해 SwiftData에서 모델 배열을 조회.
    /// - Parameter descriptor: 조회 조건이 담긴 FetchDescriptor. 기본값은 전체 조회.
    /// - Returns: 조회된 PersistentModel 배열.
    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T> = .init()) throws -> [T] {
        let fetched: [T] = try self.modelContext.fetch(descriptor)
        Log.info("fetched \(T.self) data's count", fetched.count)
        return fetched
    }
    
    /// PersistentIdentifier를 사용해 단일 모델 객체를 조회.
    /// - Parameter id: SwiftData PersistentIdentifier.
    /// - Returns: 해당 ID에 매핑되는 모델 객체, 존재하지 않으면 nil.
    public func fetch<T: PersistentModel>(id: PersistentIdentifier) -> T? {
        let object: T? = self.modelContext.model(for: id) as? T
        return object
    }
    
    /// 새로운 모델 객체를 컨텍스트에 삽입하고 즉시 저장.
    /// - Parameter item: 저장할 PersistentModel 인스턴스.
    public func insert<T: PersistentModel>(_ item: T) throws {
        self.modelContext.insert(item)
        try self.modelContext.save()
    }
    
    /// 주어진 ID에 해당하는 모델을 조회한 뒤, 비동기 쿼리 클로저를 통해 값을 수정하고 저장.
    /// - Parameters:
    ///   - id: 수정할 대상의 PersistentIdentifier.
    ///   - query: 기존 값을 인자로 받아 비동기로 수정하는 클로저.
    public func update<T: PersistentModel>(_ id: PersistentIdentifier,
                                           query: @Sendable @escaping (_ oldValue: T) async -> Void) async throws {
        if let storedItem: T = self.fetch(id: id) {
            await query(storedItem)
            try self.modelContext.save()
        } else {
            throw SwiftDatabaseActorError.storedDataIsNone
        }
    }
    
    /// 전달된 모델 객체를 삭제하고 변경사항을 저장.
    /// - Parameter item: 삭제할 PersistentModel 인스턴스.
    public func delete<T: PersistentModel>(_ item: T) throws {
        self.modelContext.delete(item)
        try self.modelContext.save()
    }
    
    /// 특정 모델 타입에 해당하는 모든 데이터를 삭제.
    /// - Parameter type: 삭제할 모델 타입.
    public func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        try self.modelContext.delete(model: T.self)
    }
    
    /// 특정 모델 타입의 데이터 존재 여부를 반환.
    /// - Parameter type: 검사할 모델 타입.
    /// - Returns: 데이터가 비어 있으면 true, 하나 이상 존재하면 false.
    public func databaseIsEmpty<T: PersistentModel>(_ type: T.Type) throws -> Bool {
        let objects: [T] = try self.fetch()
        return objects.isEmpty
    }
}


// MARK: - Dependencies 의존성 주입
extension SwiftDatabaseActor: DependencyKey {
    public static var liveValue: SwiftDatabaseActor = {
        @Dependency(\.modelContainer) var container
        return SwiftDatabaseActor(modelContainer: container)
    }()
    
    public static var testValue: SwiftDatabaseActor = {
        @Dependency(\.modelContainer) var container
        return SwiftDatabaseActor(modelContainer: container)
    }()
    
    public static var previewValue: SwiftDatabaseActor = {
        @Dependency(\.modelContainer) var container
        return SwiftDatabaseActor(modelContainer: container)
    }()
}

extension DependencyValues {
    public var createSwiftDataActor: SwiftDatabaseActor {
        get { self[SwiftDatabaseActor.self] }
        set { self[SwiftDatabaseActor.self] = newValue }
    }
}
