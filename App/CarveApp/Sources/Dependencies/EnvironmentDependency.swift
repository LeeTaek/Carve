//
//  EnvironmentDependency.swift
//  CarveApp
//
//  Created by 이택성 on 7/17/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

import Dependencies

extension String: DependencyKey {
    public static var liveValue: String {
        let id = Bundle.main.object(forInfoDictionaryKey: "CLOUDKIT_CONTAINER_ID") as? String
        return id ?? ""
    }
    
    public static var previewValue: String {
        let id = Bundle.main.object(forInfoDictionaryKey: "CLOUDKIT_CONTAINER_ID") as? String
        return id ?? ""
    }
    
    public static var testValue: String {
        let id = Bundle.main.object(forInfoDictionaryKey: "CLOUDKIT_CONTAINER_ID") as? String
        return id ?? ""
    }
}

extension DependencyValues {
    public var containerId: String {
        get { self[String.self] }
        set { self[String.self] = newValue }
    }
}
