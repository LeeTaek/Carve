//
//  AppDependencies.swift
//  CarveApp
//
//  Created by 이택성 on 10/2/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation
import SwiftData
import CarveFeature
import Data
import Domain

import Dependencies

public enum AppEnvironment {
    case dev, prod, test, preview
    
    public static func detect() -> AppEnvironment {
#if DEBUG
        if ProcessInfo.processInfo.environment["UITEST"] == "1" { return .test }
        return .dev
#else
        return .prod
#endif
    }
}

public enum AppDependencies {
    public static func configure(
        containerID: ContainerID? = nil,
        modelContainerOverride: ModelContainer? = nil,
        environment: AppEnvironment = .detect()
    ) -> (inout DependencyValues) -> Void {
        // containerId
        let resolvedContainerID: ContainerID = {
            if let id = containerID {
                return id
            }
            let cloudKitID = Bundle.main.object(forInfoDictionaryKey: "CLOUDKIT_CONTAINER_ID") as? String ?? ""
            return ContainerID(id: cloudKitID)
        }()
        
        // modelContainer 설정
        let resolvedModelContainer: ModelContainer = {
            if let override = modelContainerOverride { return override }
            return withDependencies {
                $0.containerId = resolvedContainerID
            } operation: {
                DependencyValues._current.modelContainer
            }
        }()
        
        // Domain Repository <-> Data impl 연결
        return { deps in
            // 환경 주입
            deps.containerId = resolvedContainerID
            deps.modelContainer = resolvedModelContainer
            
            // feature client
            switch environment {
            case .test:
                deps.drawingRepository = DrawingDatabase.testValue
            case .preview:
                deps.drawingRepository = DrawingDatabase.previewValue
            default:
                deps.drawingRepository = DrawingDatabase.liveValue
            }
        }
    }
}
