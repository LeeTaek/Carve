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
public class SharedUndoManager {
    private var canvasUndoManager = UndoManager()
    private var canvases: [PKCanvasView] = []
    public var isPerformingUndoRedo: Bool = false
    
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
    public static var liveValue = SharedUndoManager()
    public static var previewValue = SharedUndoManager()
}

extension DependencyValues {
    @available(*, deprecated, message: "N-Canvas 전용. 단일 Canvas 는 canvas.undoManager 를 쓰고 팔레트가 delegatesUndoToCanvas 로 위임한다 (설계 §11)")
    public var undoManager: SharedUndoManager {
        get { self[SharedUndoManager.self] }
        set { self[SharedUndoManager.self] = newValue }
    }
}
