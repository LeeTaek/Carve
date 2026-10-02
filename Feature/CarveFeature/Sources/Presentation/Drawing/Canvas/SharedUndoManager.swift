//
//  SharedUndoManager.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import Foundation
import PencilKit

import Dependencies

/// N-Canvas(절마다 `PKCanvasView`) 전용 undo 관리자.
///
/// 단일 Canvas 는 이것을 쓰지 않습니다 — `canvas.undoManager` 를 쓰고 팔레트가
/// `delegatesUndoToCanvas` 로 위임합니다 (설계 §11). flag off 롤백 경로를 위해 유지합니다 (§10-3).
///
/// `UndoManager` · `PKCanvasView` 가 MainActor 타입이라 이 타입도 MainActor 다. 리듀서는 `MainActor.assumeIsolated` 로 부른다.
/// `init` 만 `nonisolated` 다 — 의존성 기본값이 비격리 문맥에서 만든다. 그래서 `UndoManager` 는 처음 쓸 때(MainActor) 만든다.
@MainActor
public class SharedUndoManager {
    private lazy var canvasUndoManager = UndoManager()
    private var canvases: [PKCanvasView] = []
    public var isPerformingUndoRedo: Bool = false

    public nonisolated init() {}
    
    public var canUndo: Bool {
        canvasUndoManager.canUndo
    }
    
    public var canRedo: Bool {
        canvasUndoManager.canRedo
    }
    
    public func registerUndoAction(for canvas: PKCanvasView) {
        canvases.append(canvas)
        canvasUndoManager.registerUndo(withTarget: self) { target in
            target.registerRedoAction()
        }
    }
    
    public func registerRedoAction() {
        guard let last = canvases.popLast() else { return }
        canvasUndoManager.registerUndo(withTarget: self) { target in
            target.registerUndoAction(for: last)
        }
     }

    public func clear() {
        canvasUndoManager.removeAllActions()
        canvases.removeAll()
    }
    
    public func undo() {
        isPerformingUndoRedo = true
        guard let lastUndoManager = canvases.last?.undoManager else { return }
        if lastUndoManager.canUndo {
            lastUndoManager.undo()
        }
        canvasUndoManager.undo()
    }
    
    public func redo() {
        isPerformingUndoRedo = true
        canvasUndoManager.redo()
        guard let lastUndoManager = canvases.last?.undoManager else { return }
        if lastUndoManager.canRedo {
            lastUndoManager.redo()
        }
    }
}

@available(*, deprecated, message: "N-Canvas 전용. 단일 Canvas 는 canvas.undoManager 를 쓰고 팔레트가 delegatesUndoToCanvas 로 위임한다 (설계 §11)")
extension SharedUndoManager: DependencyKey {
    public nonisolated static let liveValue = SharedUndoManager()
    public nonisolated static let previewValue = SharedUndoManager()
}

extension DependencyValues {
    @available(*, deprecated, message: "N-Canvas 전용. 단일 Canvas 는 canvas.undoManager 를 쓰고 팔레트가 delegatesUndoToCanvas 로 위임한다 (설계 §11)")
    public var undoManager: SharedUndoManager {
        get { self[SharedUndoManager.self] }
        set { self[SharedUndoManager.self] = newValue }
    }
}
