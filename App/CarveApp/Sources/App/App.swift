//
//  App.swift
//  Carve
//
//  Created by 이택성 on 1/22/24.
//

import Domain
import SwiftData
import SwiftUI
import ClientInterfaces
import UIComponents

import ComposableArchitecture
import CarveFeature

/// 새기다 전체 앱의 엔트리 포인트.
/// - SwiftData의 `ModelContainer`와 TCA의 `AppCoordinatorFeature` Store를 초기화하고
///   `WindowGroup` 루트 뷰에 주입하는 역할.
@main
struct CarveApp: App {
    // Firebase 초기화
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    // 전역 네비게이션을 담당하는 Store
    private let store: StoreOf<AppCoordinatorFeature>
    // SwiftData의 ModelContainer
    let modelContainer: ModelContainer
    /// 광고용 인스턴스
    private let nativeAdClient: any NativeAdClient
    
    // 앱 시작 시 필요한 의존성(ContainerID, ModelContainer, Store)을 생성하는 생성자.
    init() {
        let containerID = Self.makeContainerID()
        let modelContainer = Self.makeModelContainer(containerID: containerID)
        self.modelContainer = modelContainer
        self.nativeAdClient = GoogleNativeAdClient()
        self.store = Self.makeStore(
            containerID: containerID,
            modelContainer: modelContainer,
            nativeAdClient: nativeAdClient
        )
    }
    
    var body: some Scene {
        WindowGroup {
            // 앱의 루트 화면. AppCoordinatorFeature의 상태/액션을 사용하는 코디네이터 뷰.
            AppCoordinatorView(store: store)
                .trackScreen(
                    "AppCoordinator",
                    parameters: [
                        "screen_name": .string("AppCoordinator"),
                        "screen_class": .string("AppCoordinatorView")
                    ]
                )
        }
        .modelContainer(modelContainer)
    }
}


// MARK: - helpers
extension CarveApp {
    /// Info.plist에 정의된 CLOUDKIT_CONTAINER_ID를 읽어와 `ContainerID`로 래핑.
    private static func makeContainerID() -> ContainerID {
        let id = Bundle.main.object(forInfoDictionaryKey: "CLOUDKIT_CONTAINER_ID") as? String ?? ""
        return ContainerID(id: id)
    }

    /// 현재 DependencyValues에 주입된 `containerId`를 사용하여 SwiftData `ModelContainer`를 생성.
    /// `DependencyValues._current.modelContainer`는 `Domain` 레이어에서 정의된 기본 구성 로직을 재사용.
    private static func makeModelContainer(containerID: ContainerID) -> ModelContainer {
        withDependencies {
            $0.containerId = containerID
        } operation: {
            DependencyValues._current.modelContainer
        }
    }

    /// AppCoordinatorFeature의 Store를 생성.
    /// 의존성 주입은 한 번에 묶어 루트 Store 생성 시점에만 수행.
    private static func makeStore(
        containerID: ContainerID,
        modelContainer: ModelContainer,
        nativeAdClient: any NativeAdClient
    ) -> StoreOf<AppCoordinatorFeature> {
        withDependencies {
            $0.containerId = containerID
            $0.modelContainer = modelContainer
            $0.nativeAdClient = nativeAdClient
            $0.analyticsClient = FirebaseAnalyticsClient()
        } operation: {
            Store(initialState: .initialState) {
                AppCoordinatorFeature()
            }
        }
    }
}
