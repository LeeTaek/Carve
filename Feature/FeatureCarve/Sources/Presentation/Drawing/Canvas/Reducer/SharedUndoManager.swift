//
//  SharedUndoManager.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Foundation
import PencilKit

import Dependencies

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

extension SharedUndoManager: DependencyKey {
    public static var liveValue = SharedUndoManager()
}

extension DependencyValues {
    public var undoManager: SharedUndoManager {
        get { self[SharedUndoManager.self] }
        set { self[SharedUndoManager.self] = newValue }
    }
}
