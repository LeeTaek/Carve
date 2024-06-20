//
//  UndoManager+Extension.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Core
import Foundation

import Dependencies

public class SharedUndoManager {
    public let undoManager = UndoManager()
    
    public func registerUndo(with target: AnyObject, selector: Selector, object: Any?) {
        Log.debug("regist Undo")
        undoManager.registerUndo(withTarget: target, selector: selector, object: object)
    }
    
    public func undo() {
        undoManager.undo()
    }
    
    public func redo() {
        undoManager.redo()
    }
    
    var canUndo: Bool {
        undoManager.canUndo
    }
    
    var canRedo: Bool {
        undoManager.canRedo
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
