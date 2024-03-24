//
//  DrawingReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/20/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Common
import CommonUI
//import DependencyInjection
import DomainRealm
import SwiftUI

import ComposableArchitecture

@Reducer
public struct DrawingReducer {
//    @Dependency(\.realmRepository) var realmRepository
    
    public struct State: Equatable, Identifiable {
        public var id: String
        public var underLineCount: Int = 1
        public var underlineOffset: [CGFloat] = [.zero]
        public var canvasState: CanvasReducer.State
        
        public init(title: TitleVO, section: Int) {
            self.id = title.title.rawValue + String(title.chapter) + String(section)
            self.canvasState = .initialState
        }
    }
    
    public enum Action: FeatureAction, CommonUI.AsyncAction, CommonUI.ScopeAction {
        case view(ViewAction)
        case inner(InnerAction)
        case async(AsyncAction)
        case scope(ScopeAction)
    }
    
    public enum ViewAction: Equatable {
        case setUnderLineCount(lineCount: Int)
        case setUnderlineOffset(offset: [CGFloat])
    }
    
    public enum InnerAction: Equatable {
        case setLinePosition
    }
    
    public enum AsyncAction: Equatable {
        case setSubscription
        case clearSubscription
        case updateSubscription
    }
    
    @CasePathable
    public enum ScopeAction {
        case canvasAction(CanvasReducer.Action)
    }

    public var body: some Reducer<State, Action> {
        Scope(state: \.canvasState,
              action: \Action.Cases.scope.canvasAction) {
            CanvasReducer()
        }
        
        Reduce { state, action in
            switch action {
            case .view(.setUnderLineCount(lineCount: let count)):
                state.underLineCount = count
                return .send(.inner(.setLinePosition))
                
            case .view(.setUnderlineOffset(offset: let offsets)):
                state.underlineOffset = offsets
                state.underLineCount = offsets.count
                
            default:
                break
            }
            return .none
        }
    }
    
}
