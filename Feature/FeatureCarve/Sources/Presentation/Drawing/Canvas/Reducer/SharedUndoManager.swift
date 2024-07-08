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
    public let canvasUndoManager = UndoManager()
    var canvases: [PKCanvasView] = []
    private var currentCanvas: PKCanvasView?
    
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
        guard let lastUndoManager = canvases.last?.undoManager else { return }
        if lastUndoManager.canUndo {
            lastUndoManager.undo()
        }

        if canvasUndoManager.canUndo {
            canvasUndoManager.undo()
        }
    }
    
    public func redo() {
        if canvasUndoManager.canRedo {
            canvasUndoManager.redo()
        }
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
