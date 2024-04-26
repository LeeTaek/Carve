//
//  BibleVO.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

public struct BibleVO: Equatable, Sendable {
    public var title: TitleVO
    public var sentence: [SentenceVO]
    
    public static let initialState = Self.init(title: .initialState,
                                               sentence: [.initialState])
    
}
