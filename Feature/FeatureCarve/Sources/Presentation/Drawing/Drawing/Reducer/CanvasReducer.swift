//
//  CanvasReducer.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/23/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Common
import DomainRealm
import PencilKit
import UIKit

import ComposableArchitecture

@Reducer
public struct CanvasReducer {
    public struct State: Equatable, Identifiable {
        public var id: String
        public var drawing: DrawingVO
        public var lineColor: UIColor
        public var lineWidth: CGFloat
        
        public init(drawing: DrawingVO,
                    lineColor: UIColor,
                    lineWidth: CGFloat) {
            self.id = "drawing.\(drawing.bibleTitle.title.rawValue).\(drawing.bibleTitle.chapter).\(drawing.section)"
            self.drawing = drawing
            self.lineColor = lineColor
            self.lineWidth = lineWidth
        }
        
        public static let initialState = Self(drawing: .init(bibleTitle: .initialState,
                                                             section: 1),
                                              lineColor: .black,
                                              lineWidth: 4)
    }
    
    public enum Action {
        case setTitle(TitleVO, Int)
        case setLine(UIColor, CGFloat)
        case selectDidFinish

    }
    
    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .setTitle(let title, let section):
                state.drawing.bibleTitle = title
                state.drawing.section = section
                
            case .setLine(let color, let width):
                state.lineColor = color
                state.lineWidth = width
                
            case .selectDidFinish:
                Log.debug("Selected Line", (state.lineColor, state.lineWidth))
                
            default:
                break
            }
            return .none
        }
    }
    
}
