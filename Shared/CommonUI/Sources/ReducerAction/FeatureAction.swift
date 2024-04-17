//
//  FeatureAction.swift
//  CommonUI
//
//  Created by 이택성 on 2/21/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation
import ComposableArchitecture

public protocol FeatureAction  {
    associatedtype ViewAction
    associatedtype InnerAction

    // view에서 사용되는 action
    static func view(_: ViewAction) -> Self
    
    // Reducer 내부적으로 사용되는 action
    static func inner(_: InnerAction) -> Self
}

public protocol ScopeAction {
    associatedtype ScopeAction

    // 자식 reducer에서 사용되는 action
    static func scope(_: ScopeAction) -> Self
}

public protocol AsyncAction {
    associatedtype AsyncAction
    
    // 비동기 action
    static func async(_: AsyncAction) -> Self
}

public protocol DelegateAction {
    associatedtype DelegateAction

    // 부모 reducer에서 사용되는 action
    static func delegate(_: DelegateAction) -> Self
}




