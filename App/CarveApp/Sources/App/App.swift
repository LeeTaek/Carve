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
        // 2.0.0 은 보류한 실행이 로그인 뒤 활성화돼도 저장소를 다시 연결하지 않는다. 실행 중 교체는 옛 컨테이너가 해제되지 않아
        // local-only 로 되돌아갔다(2026-09-28 iPadOS 18.6 실측). 소유가 확인되면 코디네이터가 재실행을 안내하고, 다음 실행의 시작 판정이 연결한다.
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

        installRuntime(modelContainer: modelContainer, syncManager: syncManager, holdState: holdState)
    }

    /// 이미 열린 컨테이너에 화면과 로컬 보존 의존성을 연결한다. 이 함수는 저장소 파일을 다시 열지 않는다.
    @MainActor
    private func installRuntime(modelContainer: ModelContainer, syncManager: PersistentCloudKitContainer, holdState: LegacySeparationHoldState) {
        let identity = CloudKitAccountIdentityClient(containerID: containerID.id)
        let ownershipProof = CloudKitStoreOwnershipProofClient(
            identity: identity, containerID: containerID.id,
            storeURL: URL.applicationSupportDirectory.appending(path: containerID.localDBPath),
            preservation: .live(localDBPath: containerID.localDBPath)
        )
        let injectedOwnership = Self.injectsStoreOwnership(containerID: containerID)

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
        // actor 와 그것을 쥔 저장소의 기본값(`static` liveValue)은 처음 읽힌 문맥의 컨테이너로 한 번 만들어져 전역에 남는다.
        // 기본값에 기대지 않고 이 실행이 연 컨테이너로 직접 만들어 넘긴다(2026-09-28 iPadOS 18.6 실측).
        let database = SwiftDatabaseActor(modelContainer: modelContainer)
        return withDependencies {
            $0.containerId = containerID
            $0.modelContainer = modelContainer
            $0.createSwiftDataActor = database
            $0.drawingRepository = SwiftDataDrawingRepository(actor: database)
            // 「확인이 필요한 필기」 의 가져오기 — 같은 actor 로 쓴다(저장소 세대 · 트랜잭션이 편집 화면과 같은 경계다).
            $0.drawingVerseImporter = SwiftDataDrawingRepository(actor: database)
            $0.favoriteVerseRepository = SwiftDataFavoriteVerseRepository(actor: database)
            // `@Dependency` 를 저장한 기본값도 처음 읽힌 runtime 문맥을 전역 캐시에 남긴다. 여기서(runtime 밖 문맥) 만들어 넘긴다.
            $0.drawingData = DrawingDatabase()
            $0.cloudSyncActivity = LiveCloudSyncActivityClient()
            $0.cloudImportArrivals = LiveCloudImportArrivalClient()
            $0.cloudAccountStatus = CloudKitAccountStatusClient()
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
            $0.verseDraftImportMarker = localPreservation
            // 설정에서 넣은 필기를 그 아래 열린 필사 화면에 알린다 — 둘이 같은 인스턴스를 봐야 한다.
            $0.localDrawingChanges = LiveLocalDrawingChangeClient()
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
