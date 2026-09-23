//
//  LocalStoreLoader.swift
//  Domain
//
//  로컬 저장소 준비 — 앱 스키마로 열지 못한 저장소를 **V1 폴백 전에** 메타데이터로 가려, 확인된 1.0.x 저장소만 V1 폴백에 태운다
//  (정책 §3 표 4행 · 테스트 계획 MIG-F1).
//

import CarveToolkit
import CoreData
import Foundation
import SwiftData

/// 로컬 저장소를 쓸 수 없는 이유. 오프라인 · iCloud 계정 문제와 **다른 축**이다 (정책 §3 표 4행).
public enum LocalStoreFailure: Hashable, Sendable {
    /// 이 앱이 아는 스키마(V1~V5)도, 확인된 1.0.x 모양도 아니다. 더 새 버전의 앱이 만들었을 수도,
    /// 출시 전에 정의가 바뀐 스키마(예: 버전을 올리지 않고 고친 V5)일 수도 있다 — **업데이트가 늘 해결책은 아니다.**
    case unknownVersion
    /// 열거나 옮기지 못했다 — 아는 스키마인데 마이그레이션이 실패했거나, 파일이 없는데 만들지 못했거나,
    /// 1.0.x 저장소를 V1 로 옮기지 못했다.
    case openFailed
    /// 저장소 정보를 읽지 못했다 — 손상됐거나 지금 접근할 수 없다.
    case unreadable
    /// 새 형식으로 열기 전에 기존 저장소를 따로 보관하지 못했다(원시 사본, 정책 §12-6 C3 ①) — 공간 부족 · 읽기 실패 ·
    /// 무결성 검사 실패. **저장소는 열지 않았다.** 보호되지 않은 채 새 모델로 열고 CloudKit 에 연결하지 않기 위해서다.
    case preservationFailed
}

/// 앱 스키마로 로컬 저장소를 연다. 열지 못하면 **V1 폴백을 하기 전에** 어떤 저장소인지 가린다.
///
/// 이전 구현(`ModelContainer.liveValue`)은 `loadIssueModelContainer` 를 전부 "버전 없는 1.0.x 저장소" 로 보고
/// V1 스키마로 **같은 파일을** 다시 열었다. 더 새 스키마의 저장소에서도 그 폴백이 성공해 파일이 `DrawingVO` 스키마로
/// 갈아치워졌고, 필사가 사라진 채 앱이 평소처럼 열렸다(테스트 계획 §5-1 DOWN-L2 · F7).
///
/// - Important: 가리기 전에 **앱 스키마로 여는 첫 시도는 이미 했다.** 그 시도가 실패했을 때 파일을 전혀 바꾸지 않았다는 보장은 없다 —
///              더 새 스키마(시험 당시 이름 V6, 지금 V7) · 손상 표본에서 바이트가 그대로인 것을 확인했을 뿐이다. 여기서 보장하는 것은 "모르는 저장소에 V1 폴백을 하지 않는다" 까지다.
enum LocalStoreLoader {
    /// 준비 결과.
    enum Outcome {
        /// 앱 스키마로 열었다.
        case ready(ModelContainer)
        /// 확인된 1.0.x 저장소를 V1 전용 컨테이너로 열었다(V1 로 옮겼다).
        /// **이번 실행에서는 필사를 저장할 수 없다** — 재실행하면 앱 스키마로 이어서 옮겨진다.
        case legacyMigration(ModelContainer)
        /// 앱 스키마로 열었지만 **CloudKit 없이** 열었다 — C14 게이트가 연결을 보류했다(정책 §12-6 C14 ③).
        case held(ModelContainer, LegacySeparationHold)
        /// 1.0.x 저장소를 V1 전용 컨테이너로, **CloudKit 없이** 열었다 — 게이트를 지나지 않은 저장소는 연결하지 않는다. 재실행해야 이어진다.
        case legacyMigrationHeld(ModelContainer, LegacySeparationHold)
        /// 쓸 수 없다. V1 폴백은 하지 않았다.
        case unavailable(LocalStoreFailure)
    }

    /// 앱 스키마로 열지 못한 저장소 파일이 무엇인지.
    enum StoreKind: Equatable {
        /// 파일이 없다.
        case missing
        /// 메타데이터를 읽지 못했다.
        case unreadable
        /// 아는 스키마 하나와 모델 해시가 정확히 맞는다 — 알고 있는 버전인데도 열지 못했다.
        case known(Schema.Version)
        /// 확인된 1.0.x 모양(`UnversionedDrawingStore`) 하나와 모델 해시가 정확히 맞는다.
        case unversionedLegacy
        /// 그 밖 — 아는 스키마도 확인된 1.0.x 모양도 아니다. 엔티티가 `DrawingVO` 하나뿐이어도 여기다.
        case unknown
    }

    /// 열지 못한 저장소를 어떻게 다룰지.
    enum Plan: Equatable {
        /// V1 전용 컨테이너로 다시 연다(기존 1.0.x 이관 경로).
        case fallbackToV1
        /// V1 폴백 없이 막는다.
        case block(LocalStoreFailure)
    }

    /// 앱이 여는 스키마 — 현재 스키마 버전의 모델 전체(`AppStoreSchema`).
    private static var appSchema: Schema {
        AppStoreSchema.schema
    }

    /// 앱 스키마 + 마이그레이션 플랜으로 연다. 실패하면 저장소를 가린 뒤 확인된 1.0.x 저장소만 V1 전용 컨테이너로 연다.
    ///
    /// 보존 영역을 주면 **열기 전에** 원시 사본을 먼저 뜬다(`RawStoreSnapshot`). 뜨지 못하면 열지 않고 막는다.
    /// 게이트를 주면 연결 직전에 C14 판정을 지난다 — 「모두 대응 있음」 일 때만 `cloudKitDatabase` 로 열고, 그 밖은 `.none` 으로 열어 보류한다.
    /// - Parameters:
    ///   - url: 저장소 파일.
    ///   - cloudKitDatabase: 앱은 `.private(컨테이너 ID)` 를 쓴다. 테스트는 `.none` 을 넘긴다 — 시뮬레이터 테스트에는 entitlement 가 없다.
    ///   - preservation: 원시 사본을 둘 곳. `nil` 이면 사본 없이 연다(기존 시험 하네스).
    ///   - separationGate: C14 게이트. `nil` 이면 판정 없이 연다(기존 시험 하네스).
    static func load(
        at url: URL,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase,
        preservation: PreservationArea? = nil,
        separationGate: LegacySeparationGate? = nil
    ) -> Outcome {
        if let preservation {
            switch RawStoreSnapshot.takeIfNeeded(storeURL: url, area: preservation) {
            case .success(let outcome):
                Log.debug("원시 사본", "\(outcome)")
            case .failure(let failure):
                Log.error("원시 사본을 뜨지 못해 저장소를 열지 않았다", "\(failure)")
                return .unavailable(.preservationFailed)
            }
        }
        if let separationGate {
            return loadThroughGate(at: url, cloudKitDatabase: cloudKitDatabase, gate: separationGate)
        }

        let loadError: Error
        do {
            return .ready(try open(url, cloudKitDatabase: cloudKitDatabase))
        } catch {
            loadError = error
        }
        switch classify(url, loadError: loadError) {
        case .fallbackToV1:
            do {
                return .legacyMigration(try openV1Only(url, cloudKitDatabase: cloudKitDatabase))
            } catch {
                Log.error("버전 없는 저장소를 V1 로 옮기지 못했다", "\(error)")
                return .unavailable(.openFailed)
            }
        case .block(let failure):
            return .unavailable(failure)
        }
    }

    /// 2.0.0 출시 경로: 원시 사본 → 로컬 마이그레이션 → CloudKit 연결.
    /// 1.3.0 무계정 필사는 미러링 저장소에 그대로 두어 첫 로그인 계정으로 전송한다.
    /// C14 사설 대응 판독·분리·삭제는 출시 조건이 아니다. 새 무계정 초안은 별도 파일에 있고 여기서 가져오지 않는다.
    /// 보존 또는 마이그레이션 실패 시 연결하지 않으며, 연결용 열기 실패도 빈 저장소로 대체하지 않는다.
    static func loadForRelease(
        at url: URL,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase,
        preservation: PreservationArea
    ) -> Outcome {
        if let stopped = prepareForRelease(at: url, preservation: preservation) {
            return stopped
        }
        do {
            return .ready(try open(url, cloudKitDatabase: cloudKitDatabase))
        } catch {
            Log.error("2.0.0 보존·마이그레이션 뒤 연결용 저장소를 열지 못했다", "\(error)")
            return .unavailable(.openFailed)
        }
    }

    /// 원시 사본과 로컬 마이그레이션만 수행한다. nil 이면 연결 가능, 그 밖은 재실행 또는 실패 처리다.
    private static func prepareForRelease(at url: URL, preservation: PreservationArea) -> Outcome? {
        switch load(at: url, cloudKitDatabase: .none, preservation: preservation) {
        case .ready:
            return nil
        case let outcome:
            return outcome
        }
    }

    /// C14 ① 의 순서 — ② CloudKit 없이 열어 마이그레이션 → ③ 판정 → ④ 보존 · 기록 → ⑦ 연결(또는 보류).
    ///
    /// `.none` 컨테이너는 이 함수 안의 지역 범위에서만 살고, 연결용 컨테이너를 만들기 전에 놓는다(「동시 열기」 규칙).
    private static func loadThroughGate(at url: URL, cloudKitDatabase: ModelConfiguration.CloudKitDatabase, gate: LegacySeparationGate) -> Outcome {
        // 시작 시간 측정(SEP-6) — 게이트는 매 실행 전체 검사다(D4). 판정 요약과 함께 남긴다.
        let clock = ContinuousClock()
        let started = clock.now
        do {
            try migrateWithoutCloudKit(url)
        } catch {
            switch classify(url, loadError: error) {
            case .block(let failure):
                return .unavailable(failure)
            case .fallbackToV1:
                // 1.0.x 모양은 `BibleDrawing` 이 없어 판정이 「알 수 없음」 이다 — 게이트를 지나지 않은 저장소는 연결하지 않는다.
                let decision = gate.decide(storeURL: url)
                Log.info("C14 게이트 — V1 폴백 경로", decision.hold.map { "\($0.reason)" } ?? "연결")
                do {
                    if let hold = decision.hold {
                        return .legacyMigrationHeld(try openV1Only(url, cloudKitDatabase: .none), hold)
                    }
                    return .legacyMigration(try openV1Only(url, cloudKitDatabase: cloudKitDatabase))
                } catch {
                    Log.error("버전 없는 저장소를 V1 로 옮기지 못했다", "\(error)")
                    return .unavailable(.openFailed)
                }
            }
        }

        let migrated = clock.now
        let decision = gate.decide(storeURL: url)
        let timing = "CloudKit 없이 열기 \(milliseconds(migrated - started)) · 판정 · 보존 \(milliseconds(clock.now - migrated))"
        switch decision {
        case .connect(let reading):
            Log.info("C14 게이트 — 연결", reading.summary, timing)
            do {
                return .ready(try open(url, cloudKitDatabase: cloudKitDatabase))
            } catch {
                Log.error("게이트를 지난 저장소를 연결해 열지 못했다", "\(error)")
                return .unavailable(.openFailed)
            }
        case .hold(let hold, let reading):
            Log.error("C14 게이트 — 연결 보류", "\(hold.reason)", reading.summary, timing)
            do {
                return .held(try open(url, cloudKitDatabase: .none), hold)
            } catch {
                Log.error("보류한 저장소를 CloudKit 없이 열지 못했다", "\(error)")
                return .unavailable(.openFailed)
            }
        }
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.1fms", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
    }

    /// 앱 스키마 + 마이그레이션 플랜으로 **CloudKit 없이** 열었다 닫는다 — 마이그레이션만 일으킨다(SEP-1 의 열기와 같다).
    private static func migrateWithoutCloudKit(_ url: URL) throws {
        _ = try open(url, cloudKitDatabase: .none)
    }

    private static func open(_ url: URL, cloudKitDatabase: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
        try ModelContainer(
            for: appSchema,
            migrationPlan: DrawingDataMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: cloudKitDatabase)
        )
    }

    private static func openV1Only(_ url: URL, cloudKitDatabase: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
        try ModelContainer(
            for: Schema([DrawingVO.self]),
            migrationPlan: MigrationPlanV1Only.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: cloudKitDatabase)
        )
    }

    /// 앱 스키마로 열지 못한 저장소를 가려 처리 방식을 정한다.
    private static func classify(_ url: URL, loadError: Error) -> Plan {
        let kind = storeKind(at: url)
        let isLoadIssue = (loadError as? SwiftDataError) == .loadIssueModelContainer
        Log.error("로컬 저장소를 앱 스키마로 열지 못했다", "\(kind)", "\(loadError)")
        return plan(for: kind, isLoadIssue: isLoadIssue)
    }

    /// 열지 못한 저장소를 어떻게 다룰지. 순수 함수라 테스트로 고정한다.
    ///
    /// | 저장소 | 처리 |
    /// |---|---|
    /// | 확인된 1.0.x 모양 (`loadIssueModelContainer` 일 때만) | V1 폴백 — 이전 구현의 조건을 좁힌 것이다 |
    /// | 아는 버전 · 파일 없음 | 막기(`openFailed`) |
    /// | 모르는 모델 | 막기(`unknownVersion`) — **V1 폴백이 필사를 지우던 경우다** |
    /// | 메타데이터를 읽지 못함 | 막기(`unreadable`) |
    static func plan(for kind: StoreKind, isLoadIssue: Bool) -> Plan {
        switch kind {
        case .unversionedLegacy: isLoadIssue ? .fallbackToV1 : .block(.openFailed)
        case .known, .missing: .block(.openFailed)
        case .unknown: .block(.unknownVersion)
        case .unreadable: .block(.unreadable)
        }
    }

    /// 메타데이터만 읽어 저장소를 가린다. 이 함수는 저장소를 열지 않는다 — 열면 마이그레이션이 파일을 바꿀 수 있다.
    ///
    /// 모델 해시(`NSStoreModelVersionHashes`)에는 앱 엔티티만 담긴다. persistent history(`ACHANGE` …)와 CloudKit 미러링
    /// (`ANSCK…`) 엔티티는 들어가지 않는 것을 테스트 저장소와 시뮬레이터 앱 저장소(iCloud 미로그인)에서 확인했다(테스트 계획 §5-1 MIG-F1).
    /// - Parameters:
    ///   - url: 저장소 파일.
    ///   - knownSchemas: 앱이 아는 스키마.
    ///   - unversionedModels: V1 폴백을 허용할 1.0.x 모양. **해시가 정확히 맞아야 한다** — 엔티티 이름만 같은 저장소는 막는다.
    static func storeKind(
        at url: URL,
        knownSchemas: [any VersionedSchema.Type] = DrawingDataMigrationPlan.schemas,
        unversionedModels: [[any PersistentModel.Type]] = UnversionedDrawingStore.modelSets
    ) -> StoreKind {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let metadata: [String: Any]
        do {
            metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        } catch {
            Log.error("로컬 저장소 메타데이터를 읽지 못했다", "\(error)")
            return .unreadable
        }
        guard metadata[NSStoreModelVersionHashesKey] is [String: Data] else { return .unreadable }

        if let schema = knownSchemas.first(where: { matches($0.models, metadata: metadata) }) {
            return .known(schema.versionIdentifier)
        }
        return unversionedModels.contains { matches($0, metadata: metadata) } ? .unversionedLegacy : .unknown
    }

    /// 모델 전체의 엔티티 해시가 저장소 메타데이터와 정확히 맞는가.
    private static func matches(_ models: [any PersistentModel.Type], metadata: [String: Any]) -> Bool {
        NSManagedObjectModel.makeManagedObjectModel(for: models)?
            .isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) == true
    }

    /// 저장소를 쓸 수 없을 때 앱이 붙잡을 빈 컨테이너.
    ///
    /// 편집 화면에 들어가지 않으므로 쓰일 일이 없다. 그래도 **메모리에만 있고 CloudKit 에 붙지 않는다** — 잘못 쓰이더라도
    /// 저장소 파일 · 서버를 건드리지 않는다. 기본값(`.automatic`)은 앱의 CloudKit · App Group 설정을 따라가므로 둘 다 끈다.
    /// 저장 자체는 거절하지 않으므로 진입을 막는 쪽(`LaunchRoute` · 코디네이터의 진입 직전 확인)이 경계다.
    /// - Note: 저장까지 거절하려고 `allowsSave: false` 를 줬더니 만들어지지 않았다 — 메모리 저장소는 `/dev/null` 의 SQLite 라
    ///         읽기 전용으로 열 수 없다(2026-09-17, NSCocoaErrorDomain 257).
    static func makeUnavailableStandIn() throws -> ModelContainer {
        try ModelContainer(
            for: appSchema,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        )
    }
}
