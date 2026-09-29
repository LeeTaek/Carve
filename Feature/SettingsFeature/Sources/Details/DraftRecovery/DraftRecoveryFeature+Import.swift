//
//  DraftRecoveryFeature+Import.swift
//  SettingsFeature
//
//  「확인이 필요한 필기」 의 견주기와 넣기 · 바꾸기 (정책 §12-6 ④ 가져오기, 2026-09-29).
//

import CarveToolkit
import Domain
import Foundation

import ComposableArchitecture

extension DraftRecoveryFeature {
    // MARK: - 견주기

    /// 견줄 때 그 장만 읽는다 — 목록은 지금 필기의 바이트를 들고 있지 않다. 남겨 둔 필기도 **다시 읽어** 넣으면 무엇이 되는지 판정한다
    /// (`VerseDraftImportRule`). 읽기 **전후로** 계정 근거가 목록의 것과 같은지 본다(P0-1).
    func compare(_ item: Item, stamp: Stamp) -> Effect<Action> {
        .run { [reader, repository, editEnvironment] send in
            guard let reader else {
                await send(.currentFailed(itemID: item.id, stamp: stamp, "이 iPad의 보존 영역을 열지 못했어요."))
                return
            }
            let environment = await editEnvironment.current()
            guard Stamp(environment) == stamp else {
                await send(.environmentChanged(Stamp(environment)))
                return
            }
            do {
                let current = try await VerseDraftRecoveryQuery(reader: reader, repository: repository)
                    .currentVerse(chapter: item.chapter, verse: item.verse)
                let translation = Translation(rawValue: item.key.translation) ?? .NKRV
                let draft = try await reader.drafts(in: item.scope, chapter: item.chapter, translation: translation)
                    .first { $0.key == item.key }
                let after = Stamp(await editEnvironment.current())
                guard after == stamp else {
                    // 읽는 사이 계정이 바뀌었다 — 읽은 필기는 다른 계정의 저장소 내용일 수 있다. 내지 않는다.
                    await send(.environmentChanged(after))
                    return
                }
                guard let draft, draft.revision == item.revision else {
                    // 목록을 읽은 뒤 그 필기가 이어 쓰였거나 사라졌다 — 본 것과 다른 것을 넣지 않게 목록부터 다시 읽는다.
                    await send(.draftChanged(itemID: item.id, stamp: stamp))
                    return
                }
                let check = VerseDraftImportRule.check(draft: draft, current: current, knowledge: environment.knowledge)
                await send(.currentLoaded(itemID: item.id, stamp: stamp, ink: current?.lineData, updatedAt: current?.updateDate, check: check))
            } catch {
                Log.error("확인이 필요한 필기 — 지금 필기를 읽지 못했다", item.place, "\(error)")
                await send(.currentFailed(itemID: item.id, stamp: stamp, "지금 그 절의 필기를 읽지 못했어요. 없다는 뜻은 아니에요."))
            }
        }
        .cancellable(id: CancelID.compare, cancelInFlight: true)
    }

    // MARK: - 넣기 · 바꾸기

    /// 견주고 있는 필기를 넣는다. 지웠던 내용이 다시 들어갈 수 있으면 넣지 않고 먼저 묻는다.
    func importTapped(_ state: inout State) -> Effect<Action> {
        guard let target = importable(state) else { return .none }
        if let caution = target.check.caution {
            state.pendingCaution = caution
            return .none
        }
        return startImport(&state, target: target, acknowledged: nil)
    }

    /// 물은 주의를 확인했다 — 그 주의가 지금 판정의 것일 때만 넣는다.
    func cautionConfirmed(_ state: inout State) -> Effect<Action> {
        guard let caution = state.pendingCaution, let target = importable(state), target.check.caution == caution else {
            state.pendingCaution = nil
            return .none
        }
        state.pendingCaution = nil
        return startImport(&state, target: target, acknowledged: caution)
    }

    /// 지금 넣을 수 있는 견주기 — 그 필기 · 판정 · 근거.
    private struct ImportTarget {
        let item: Item
        let check: VerseDraftImportCheck
        let stamp: Stamp
    }

    /// 지금 넣을 수 있는 견주기 — 판정이 넣기 · 바꾸기이고, 넣는 중이 아니며, 지금 근거로 쓸 수 있다.
    private func importable(_ state: State) -> ImportTarget? {
        guard let comparison = state.comparison, !comparison.isLoading, comparison.failure == nil,
              let check = comparison.check, check.action == .insert || check.action == .replace,
              state.importingItemID == nil,
              let stamp = state.stamp, stamp.importBlock == nil,
              let item = state.comparableItem(id: comparison.itemID) else { return nil }
        return ImportTarget(item: item, check: check, stamp: stamp)
    }

    /// 넣는다 — 넣기 직전에 환경 · 필기 · 지금 필기를 다시 본다(`VerseDraftImporter`). 저장을 마치면 열린 필사 화면에 알린다.
    private func startImport(_ state: inout State, target: ImportTarget, acknowledged: VerseDraftImportCheck.Caution?) -> Effect<Action> {
        let item = target.item, check = target.check, stamp = target.stamp
        state.importingItemID = item.id
        state.importMessage = nil
        let request = VerseDraftImportRequest(
            key: item.key, scope: item.scope, revision: item.revision, expectedCurrentFingerprint: check.currentFingerprint,
            acknowledgedCaution: acknowledged
        )
        return .run { [reader, repository, verseImporter, importMarker, editEnvironment, localChanges, date] send in
            guard let reader, let verseImporter, let importMarker else {
                await send(.imported(itemID: item.id, place: item.place, .failure(ImportFailure(message: "가져오기 경계가 주입되지 않았다"))))
                return
            }
            let environment = await editEnvironment.current()
            guard Stamp(environment) == stamp else {
                // 고르는 사이 계정 근거가 바뀌었다 — 넣지 않고 새 근거로 다시 읽는다.
                await send(.environmentChanged(Stamp(environment)))
                return
            }
            let importer = VerseDraftImporter(
                reader: reader, repository: repository, writer: verseImporter, marker: importMarker, now: { date.now }
            )
            do {
                let result = try await importer.importDraft(request, environment: environment)
                if case .imported = result {
                    // 필사 화면 위의 패널이다 — 그 아래 열린 장이 이 절을 다시 읽어 반영하게 알린다.
                    localChanges.post(LocalDrawingChange(chapter: item.chapter, date: date.now))
                }
                await send(.imported(itemID: item.id, place: item.place, .success(result)))
            } catch {
                Log.error("확인이 필요한 필기 — 넣지 못했다. 지금 필기와 남겨 둔 필기는 그대로다", item.place, "\(error)")
                await send(.imported(itemID: item.id, place: item.place, .failure(ImportFailure(message: "\(error)"))))
            }
        }
    }

    /// 넣기의 결과 — **저장을 마친 뒤에만** 완료를 알린다.
    func finishImport(
        _ state: inout State, itemID: String, place: String, result: Result<VerseDraftImporter.Result, ImportFailure>
    ) -> Effect<Action> {
        // 계정 근거가 바뀌어 목록을 버렸으면 그 결과도 버린다 — 새 근거로 다시 읽은 목록이 사실을 보인다.
        guard state.importingItemID == itemID else { return .none }
        state.importingItemID = nil
        switch result {
        case .success(.imported(let previousKept, _)):
            state.importMessage = ImportMessage(text: DraftRecoveryCopy.imported(place, previousKept: previousKept), needsAttention: false)
            return reloadAfterImport(&state)
        case .success(.alreadyApplied):
            state.importMessage = ImportMessage(text: DraftRecoveryCopy.alreadyApplied(place), needsAttention: false)
            return reloadAfterImport(&state)
        case .success(.draftChanged):
            state.importMessage = ImportMessage(text: DraftRecoveryCopy.draftChanged, needsAttention: true)
            return reloadAfterImport(&state)
        case .success(.currentChanged), .success(.cautionRequired):
            // 견준 뒤 그 절이 바뀌었거나 물을 것이 생겼다 — 넣지 않았다. 다시 견주어 새 판정을 보인다.
            state.importMessage = ImportMessage(text: DraftRecoveryCopy.currentChanged, needsAttention: true)
            guard let item = state.comparableItem(id: itemID), let stamp = state.stamp else { return reloadAfterImport(&state) }
            state.comparison = Comparison(itemID: itemID)
            state.pendingCaution = nil
            return compare(item, stamp: stamp)
        case .success(.unavailable):
            state.importMessage = ImportMessage(text: DraftRecoveryCopy.importUnavailable, needsAttention: true)
        case .success(.blocked(let block)):
            state.importMessage = ImportMessage(text: DraftRecoveryCopy.importBlocked(block), needsAttention: true)
        case .failure:
            state.importMessage = ImportMessage(text: DraftRecoveryCopy.importFailed, needsAttention: true)
        }
        return .none
    }

    /// 넣은 뒤(또는 넣을 것이 없어진 뒤) 견주기를 접고 목록을 다시 읽는다 — 넣은 필기는 이미 반영된 것이라 목록에서 빠진다.
    private func reloadAfterImport(_ state: inout State) -> Effect<Action> {
        closeComparison(&state)
        return .merge(.cancel(id: CancelID.compare), startLoad(&state))
    }
}
