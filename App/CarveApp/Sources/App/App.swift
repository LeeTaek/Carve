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
/// 저장소 ownership preflight 를 마친 뒤 ModelContainer 와 TCA Store 를 만든다.
@main
struct CarveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private let containerID: ContainerID
    private let purchaseClient: any PurchaseClient
    private let nativeAdClient: any NativeAdClient
    private let adConsent: AdConsentCoordinator
    /// 실행 뒤에 도착하는 본문 모양 iCloud 백업도 받도록 앱 수명 동안 유지한다.
    private let sentenceSettingBackup: SentenceSettingCloudBackup

    init() {
        let purchaseClient = StoreKitPurchaseClient()
        self.purchaseClient = purchaseClient
        SingleCanvasFlag.resetStoredValueOnce(in: .standard)

        let sentenceSettingBackup = SentenceSettingCloudBackup()
        sentenceSettingBackup.start()
        self.sentenceSettingBackup = sentenceSettingBackup

        #if DEBUG
        UITestLaunchChapter.apply()
        #endif

        let containerID = Self.makeContainerID()
        self.containerID = containerID
        let adConsent = AdConsentCoordinator(purchases: purchaseClient)
        self.adConsent = adConsent
        self.nativeAdClient = GoogleNativeAdClient(consent: adConsent, purchases: purchaseClient)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-CanvasScrollSpike") {
                // SwiftData 사용자 저장소와 연결되지 않는 Debug 전용 레이아웃 하네스.
                CanvasScrollSpikeView()
            } else {
                startupView
            }
            #else
            startupView
            #endif
        }
    }

    private var startupView: some View {
        AppStartupView(
            containerID: containerID,
            purchaseClient: purchaseClient,
            nativeAdClient: nativeAdClient,
            adConsent: adConsent,
            sentenceSettingBackup: sentenceSettingBackup
        )
    }

    private static func makeContainerID() -> ContainerID {
        let id = Bundle.main.object(forInfoDictionaryKey: "CLOUDKIT_CONTAINER_ID") as? String ?? ""
        return ContainerID(id: id)
    }
}

private struct AppRuntime {
    let modelContainer: ModelContainer
    let store: StoreOf<AppCoordinatorFeature>
}

/// 계정 확인과 저장소 소유 증명이 끝나기 전에는 `.private` ModelContainer 를 만들지 않는다.
private struct AppStartupView: View {
    let containerID: ContainerID
    let purchaseClient: any PurchaseClient
    let nativeAdClient: any NativeAdClient
    let adConsent: AdConsentCoordinator
    let sentenceSettingBackup: any SentenceSettingBackupClient

    @State private var runtime: AppRuntime?
    @State private var didStart = false

    var body: some View {
        Group {
            if let runtime {
                rootView(runtime)
                    .modelContainer(runtime.modelContainer)
            } else {
                ProgressView("필사 저장소와 계정 소유를 확인하고 있어요")
                    .task { await startIfNeeded() }
            }
        }
    }

    /// 소유 근거가 없거나 계정을 확인하지 못하면 Domain bootstrap 이 local-only 컨테이너와 보류 상태를 돌려준다.
    @MainActor
    private func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true

        let storeURL = URL.applicationSupportDirectory.appending(path: containerID.localDBPath)
        let preservation = PreservationArea.live(localDBPath: containerID.localDBPath)
        let identity = CloudKitAccountIdentityClient(containerID: containerID.id)
        let ownershipProof = CloudKitStoreOwnershipProofClient(
            identity: identity,
            containerID: containerID.id,
            storeURL: storeURL,
            preservation: preservation
        )
        let syncManager = PersistentCloudKitContainer()
        let holdState = LegacySeparationHoldState()
        let injectedOwnership = Self.injectsStoreOwnership(containerID: containerID)
        let modelContainer = await ReleaseStoreBootstrapper.load(
            containerID: containerID,
            identity: identity,
            ownershipProof: ownershipProof,
            syncManager: syncManager,
            holdState: holdState,
            injectsOwnership: injectedOwnership
        )

        let localPreservation = LocalPreservationWriter(
            area: .live(localDBPath: containerID.localDBPath),
            eraseState: .live(localDBPath: containerID.localDBPath)
        )
        let drawingEditEnvironment = LiveDrawingEditEnvironment(
            identity: identity,
            containerID: containerID.id,
            stateStore: FileEraseStateStore(area: .live(localDBPath: containerID.localDBPath)),
            localPreservation: localPreservation,
            holdState: holdState,
            ownershipProof: ownershipProof,
            injectsOwnership: injectedOwnership
        )
        let store = Self.makeStore(
            containerID: containerID,
            modelContainer: modelContainer,
            syncManager: syncManager,
            holdState: holdState,
            nativeAdClient: nativeAdClient,
            adConsentClient: adConsent,
            purchaseClient: purchaseClient,
            sentenceSettingBackup: sentenceSettingBackup,
            drawingEditEnvironment: drawingEditEnvironment,
            localPreservation: localPreservation
        )
        Task { await drawingEditEnvironment.start() }
        runtime = AppRuntime(modelContainer: modelContainer, store: store)
    }

    /// 앱의 루트 화면. 준비된 ModelContainer 와 Store 를 사용한다.
    private func rootView(_ runtime: AppRuntime) -> some View {
        AppCoordinatorView(store: runtime.store)
            .trackScreen(
                "AppCoordinator",
                parameters: [
                    "screen_name": .string("AppCoordinator"),
                    "screen_class": .string("AppCoordinatorView")
                ]
            )
            .task { await adConsent.gatherConsent() }
            .onOpenURL { url in
                runtime.store.send(.openedURL(url))
            }
    }

    /// ACC-1 2차 전용 소유 주입(DEBUG · 시뮬레이터 · dev 컨테이너 · 실행 인자).
    private static func injectsStoreOwnership(containerID: ContainerID) -> Bool {
        #if DEBUG
        guard StoreOwnershipInjection.isEnabled(containerID: containerID) else { return false }
        print("⚠️ 소유 주입(DEBUG · 시뮬레이터 · dev 컨테이너) — 소유 증명이 아니다. ACC-1 2차 시험 전용이며 결과는 주입 없는 시험과 따로 기록한다")
        return true
        #else
        return false
        #endif
    }

    /// AppCoordinatorFeature 의 Store 와 앱 의존성을 한 번에 만든다.
    private static func makeStore(
        containerID: ContainerID,
        modelContainer: ModelContainer,
        syncManager: PersistentCloudKitContainer,
        holdState: LegacySeparationHoldState,
        nativeAdClient: any NativeAdClient,
        adConsentClient: any AdConsentClient,
        purchaseClient: any PurchaseClient,
        sentenceSettingBackup: any SentenceSettingBackupClient,
        drawingEditEnvironment: any DrawingEditEnvironmentClient,
        localPreservation: LocalPreservationWriter
    ) -> StoreOf<AppCoordinatorFeature> {
        withDependencies {
            $0.containerId = containerID
            $0.modelContainer = modelContainer
            $0.clouodKitSyncManager = syncManager
            $0.legacySeparationHoldState = holdState
            $0.nativeAdClient = nativeAdClient
            $0.adConsentClient = adConsentClient
            $0.purchaseClient = purchaseClient
            $0.sentenceSettingBackup = sentenceSettingBackup
            $0.drawingEditEnvironment = drawingEditEnvironment
            $0.localPreservationWriter = localPreservation
            $0.verseDraftStore = localPreservation
            $0.verseDraftRecoveryReader = localPreservation
            $0.verseDraftUnreadableCleaner = localPreservation
            $0.photoLibraryClient = PhotoKitLibraryClient()
            $0.widgetVerseClient = AppGroupWidgetVerseClient()
            $0.analyticsClient = FirebaseAnalyticsClient()
        } operation: {
            Store(initialState: .initialState) {
                AppCoordinatorFeature()
            }
        }
    }
}
