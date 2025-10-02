//
//  DrawingRepository.swift
//  Domain
//
//  Created by 이택성 on 10/2/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import Dependencies

public protocol DrawingRepository: Sendable {
    // 한 장 전체
    func fetch(title: TitleVO) async throws -> [BibleDrawing]
    // 해당 drawing의 아이디를 기준으로 필사데이터 불러옴
    func fetch(drawing: BibleDrawing) async throws -> BibleDrawing?
    // 해당 절의 필사 데이터 모두 가져오기
    func fetchDrawings(title: TitleVO, verse: Int) async throws -> [BibleDrawing]
    // 갱신
    func updateDrawing(drawing: BibleDrawing) async throws
    func updateDrawings(drawings: [BibleDrawing]) async throws
    // 전부 삭제
    func deleteAll() async throws
    // 데이터베이스 빈 여부
    func databaseIsEmpty() async throws -> Bool
}

public struct UnimplementedDrawingRepository: DrawingRepository {
    public func fetch(title: TitleVO) async throws -> [BibleDrawing] {
        return []
    }
    
    public func fetch(drawing: BibleDrawing) async throws -> BibleDrawing? {
        return nil
    }
    
    public func fetchDrawings(title: TitleVO, verse: Int) async throws -> [BibleDrawing] {
        return []
    }
    
    public func updateDrawing(drawing: BibleDrawing) async throws {}
    
    public func updateDrawings(drawings: [BibleDrawing]) async throws {}
    
    public func deleteAll() async throws {}
    
    public func databaseIsEmpty() async throws -> Bool { return false }
}


public enum DrawingRepositoryKey: DependencyKey {
    public static var liveValue: any DrawingRepository = UnimplementedDrawingRepository()
}


public extension DependencyValues {
    var drawingRepository: any DrawingRepository {
        get { self[DrawingRepositoryKey.self] }
        set { self[DrawingRepositoryKey.self] = newValue }
    }
}
