//
//  LiveBackupImporter+Apply.swift
//  Domain
//
//  Created by Claude on 10/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//
//  「백업 불러오기」 의 적용 — 장마다 최신 환경 · 쓰기 게이트 · 대상 계정을 다시 보고 한 트랜잭션씩 쓴다 (설계 docs/backup-import-design.md §4-3 · §6-2).
//

import CarveToolkit
import Foundation

extension LiveBackupImporter {
    /// 검사 결과를 장 단위로 적용한다(필사책 → 권 순서 → 장 순서).
    ///
    /// 시작할 때 저장소 세대를 한 번 읽고, 다른 작업 기록을 지운 뒤(새 적용이 앞선 작업을 대신한다) 작업을 「적용 중」 으로 남긴다.
    ///
    /// **필사책 목록(형식 2)을 장보다 먼저 쓴다** — 최신 환경 · 쓰기 게이트 · 대상 계정을 장과 같은 규칙으로 본 뒤
    /// `DrawingBackupRestoring.restoreNotebooks`(같은 ID 면 `updatedAt` 이 늦은 쪽) 한 트랜잭션. 행보다 먼저 써서 불러오는 동안 다른 필사책이
    /// 「이름 없는 필사책」 으로 보이는 틈을 줄인다. 이어 하기도 다시 쓴다(같은 값이면 바뀌지 않는다). 그다음 장마다:
    /// 1. 작업 기록에 끝난 장이면 건너뛴다(이어 하기 — 다시 써도 같은 지문은 `skipSame` 이라 결과는 같다).
    /// 2. `DrawingEditEnvironmentClient.current()` 로 **최신 환경**을 읽는다 — 쓰기 게이트가 막혔으면 `.blocked(사유)`, 저장소 소유가
    ///    대상 계정과 다르면 `.accountChanged` 로 그 장부터 멈춘다.
    /// 3. `DrawingBackupRestoring.restore` — 같은 actor 구간에서 세대를 확인하고 다시 판정해 한 트랜잭션으로 쓴다. 세대가 시작 때와
    ///    다르면(그 사이 「모든 필사 삭제」) `.generationChanged` 로 멈추고 끝난 장을 비운다(그 장들의 행도 지워졌다).
    /// 4. 작업 기록에 그 장을 끝남으로 남기고, 저장소가 바뀌었으면 `LocalDrawingChange` 를 보내고, 진행을 알린다.
    /// 5. 다음 장이 있으면 그 환경의 서버 작업 표가 아직 유효한지 본다 — 아니면 `.accountChanged` 로 멈춘다.
    ///
    /// 멈춰도 쓴 장은 되돌리지 않는다(이미 동기화됐을 수 있다). 다만 계정이 바뀌거나 쓰기 게이트가 막혀 멈추면 작업 기록의 끝난 장을 비워
    /// 이어 할 때 처음부터 다시 판정한다(`forgetDoneChapters` — 로그아웃 정리로 쓴 행이 사라질 수 있다). 다 쓰면 작업 기록 · 암호화 사본을 지운다.
    /// 어느 쪽이든 평문 작업 폴더는 지운다.
    /// - Parameters:
    ///   - inspection: `inspect` · `resume` · `restart` 의 결과.
    ///   - progress: 장 단위 진행.
    /// - Returns: `.completed` 또는 멈춘 사유와 끝난 장 · 수.
    /// - Throws: `inspectionExpired`(평문을 이미 지웠다) · `jobNotFound`(작업을 버렸다) · `storeWriteFailed`(그 장을 읽거나 쓰지 못했다),
    ///   취소면 `CancellationError` — 쓴 장은 그대로 두고 작업 기록을 「멈춤」 으로 남긴다. 부작용: 저장소 쓰기 · 작업 기록 쓰기 · 파일 삭제.
    public func apply(_ inspection: BackupInspection, progress: @Sendable (BackupProgress) async -> Void) async throws -> BackupImportReport {
        guard let payload = inspection.payload, let work = inspection.workDirectory,
              FileManager.default.fileExists(atPath: payload.blobDirectory.deletingLastPathComponent().path) else {
            throw BackupImportError.inspectionExpired
        }
        defer { removeWorkDirectory(work) }
        guard var record = jobs.load(inspection.jobID) else { throw BackupImportError.jobNotFound }
        jobs.removeAll(except: record.jobID)
        record.status = .applying
        record.totalChapters = inspection.preview.chapters.count
        record.updatedAt = now()
        persist(record)

        let pages = inspection.preview.chapters
        let itemsByPage = BackupImportPlanner.itemsByPage(payload.items)
        let generation = await database.backupStoreGeneration()
        let alreadyDone = Set(record.doneChapters)
        let remaining = pages.filter { !alreadyDone.contains($0) }
        var doneCount = pages.count - remaining.count
        await progress(BackupProgress(done: doneCount, total: pages.count))

        // 필사책 목록 — 장보다 먼저, 장과 같은 게이트를 지난 뒤에만 쓴다.
        if !payload.manifest.notebooks.isEmpty {
            let current = await environment.current()
            if let stop = Self.stopReason(before: "필사책 목록", environment: current, targetScope: inspection.targetScope) {
                let report = Self.report(stop, record: record)
                Self.forgetDoneChapters(&record)
                markStopped(&record)
                return report
            }
            do {
                try Task.checkCancellation()
                let outcome = try await restorer.restoreNotebooks(payload.manifest.notebooks, generation: generation)
                Log.info(
                    "불러오기 — 필사책 목록을 썼다",
                    "새=\(outcome.inserted)", "바꿈=\(outcome.updated)", "그대로=\(outcome.unchanged)", "건너뜀=\(outcome.skipped)"
                )
            } catch DrawingRepositoryError.staleStoreGeneration {
                Log.error("불러오기 — 적용 중 모든 필사가 지워져 멈춘다", "필사책 목록")
                record.doneChapters = []
                record.tally = BackupImportTally()
                markStopped(&record)
                return Self.report(.generationChanged, record: record)
            } catch {
                markStopped(&record)
                throw Self.applyFailure(error, label: "필사책 목록")
            }
        }

        for (index, page) in remaining.enumerated() {
            let current = await environment.current()
            if let stop = Self.stopReason(before: Self.label(page), environment: current, targetScope: inspection.targetScope) {
                let report = Self.report(stop, record: record)
                Self.forgetDoneChapters(&record)
                markStopped(&record)
                return report
            }
            let outcome: BackupChapterRestoreOutcome
            do {
                try Task.checkCancellation()
                let command = try Self.command(for: itemsByPage[page] ?? [], payload: payload)
                outcome = try await restorer.restore(command, page: page, generation: generation)
            } catch DrawingRepositoryError.staleStoreGeneration {
                Log.error("불러오기 — 적용 중 모든 필사가 지워져 멈춘다", Self.label(page))
                // 앞서 쓴 장의 행도 지워졌다 — 이어 하면 처음부터 다시 판정한다.
                record.doneChapters = []
                record.tally = BackupImportTally()
                markStopped(&record)
                return Self.report(.generationChanged, record: record)
            } catch {
                markStopped(&record)
                throw Self.applyFailure(error, label: Self.label(page))
            }

            record.doneChapters.append(page)
            record.tally.add(outcome)
            record.updatedAt = now()
            persist(record)
            if outcome.changedStore {
                changes.post(LocalDrawingChange(page: page, date: now()))
            }
            doneCount += 1
            await progress(BackupProgress(done: doneCount, total: pages.count))

            // 다음 장으로 가기 전에, 이 장을 쓴 환경의 서버 작업 표가 아직 유효한지 본다.
            if index < remaining.count - 1, let token = current.serverWork, await !environment.isCurrent(token) {
                Log.error("불러오기 — 장을 쓴 뒤 서버 작업 표가 무효가 돼 멈춘다", Self.label(page))
                let report = Self.report(.accountChanged, record: record)
                Self.forgetDoneChapters(&record)
                markStopped(&record)
                return report
            }
        }

        jobs.remove(record.jobID)
        Log.info(
            "불러오기 — 모든 장을 썼다",
            "장=\(pages.count)", "새=\(record.tally.new)", "보관=\(record.tally.archived)",
            "지운 절 보호=\(record.tally.protectedCleared)", "같음=\(record.tally.same)", "고정=\(record.tally.pinned)"
        )
        return .completed(record.tally)
    }

    /// 장 하나(또는 필사책 목록)를 쓰기 전에 멈출 까닭 — 쓰기 게이트가 막혔거나 저장소 소유가 대상 계정과 다르면(대상 계정이 없던 검사 포함).
    /// - Parameters:
    ///   - label: 로그에 남길 쓸 것의 이름(장이면 `label(_:)`).
    ///   - environment: 방금 읽은 최신 환경.
    ///   - targetScope: 검사 때 정한 대상 계정.
    /// - Returns: 멈출 까닭. 써도 되면 nil. 부작용 없음(로그만).
    static func stopReason(before label: String, environment: DrawingEditEnvironment, targetScope: AccountScope?) -> BackupImportStop? {
        if let block = SyncedWriteBlock.check(environment) {
            Log.error("불러오기 — 쓰기 게이트가 막혀 이 장부터 멈춘다", label, "사유=\(block)")
            return .blocked(block)
        }
        guard let targetScope, environment.storeOwnership == targetScope else {
            Log.error("불러오기 — 저장소 소유가 대상 계정과 달라 이 장부터 멈춘다", label)
            return .accountChanged
        }
        return nil
    }

    /// 장 하나의 복원 명령 — 그 장 항목과, 항목이 가리키는 blob 바이트 전부(지원 판정이 미리보기와 같도록 메타데이터 blob 까지).
    /// - Throws: 평문 작업 폴더의 blob 을 읽지 못하면 `BackupFormatError.missingBlob`. 부작용 없음(읽기만 한다).
    static func command(for items: [BackupItem], payload: BackupPayload) throws -> BackupChapterRestoreCommand {
        var blobs: [String: Data] = [:]
        for item in items {
            for name in [item.inkBlob, item.metadataBlob].compactMap({ $0 }) where blobs[name] == nil {
                blobs[name] = try payload.blob(named: name)
            }
        }
        return BackupChapterRestoreCommand(items: items, blobs: blobs)
    }

    /// 계정이 바뀌거나 쓰기 게이트가 막혀 멈출 때 작업 기록의 끝난 장 · 수를 비운다 — 이어 하면 처음부터 다시 판정한다.
    ///
    /// iCloud 로그아웃 · 계정 전환은 시스템이 이 기기의 동기화 데이터를 비워, 아직 올라가지 않은 장의 행이 사라질 수 있다(2.1.0 출시 시험 D12).
    /// 끝난 장을 남겨 두면 이어 하기가 그 장을 건너뛰어 빠진 채 끝나고 결과 수도 실제와 달라진다. 다시 판정하면 남은 행은 같은 지문이라
    /// 건너뛰고(`skipSame`) 사라진 행만 다시 넣는다 — 「모든 필사 삭제」 로 세대가 바뀌어 멈출 때(`generationChanged`)와 같은 규칙이다.
    /// 이번 실행의 보고는 비우기 전에 만든다(멈춘 화면이 이번에 넣은 수를 보인다).
    /// - Parameter record: 작업 기록 — 끝난 장 · 수를 비운다. 부작용 없음(쓰기는 `markStopped`).
    static func forgetDoneChapters(_ record: inout BackupImportJobRecord) {
        record.doneChapters = []
        record.tally = BackupImportTally()
    }

    /// 작업을 「멈춤」 으로 남긴다 — 이어 하기(`pendingJob`) 대상이 된다.
    /// - Parameter record: 작업 기록 — 상태 · 시각을 바꿔 쓴다. 부작용: 작업 기록 쓰기.
    func markStopped(_ record: inout BackupImportJobRecord) {
        record.status = .stopped
        record.updatedAt = now()
        persist(record)
    }

    /// 멈춘 까닭과 작업 기록으로 보고를 만든다 — 끝난 장(필사책 → 권 → 장 순서)과 그 장들의 수.
    /// - Returns: 보고. 부작용 없음.
    static func report(_ reason: BackupImportStop, record: BackupImportJobRecord) -> BackupImportReport {
        let done = BackupImportPlanner.ordered(record.doneChapters)
        switch reason {
        case .blocked(let block): return .blocked(block, doneChapters: done, tally: record.tally)
        case .accountChanged: return .accountChanged(doneChapters: done, tally: record.tally)
        case .generationChanged: return .generationChanged(doneChapters: done, tally: record.tally)
        }
    }

    /// 적용 중 오류를 알릴 오류로 바꾼다 — 취소는 그대로, 평문 blob 을 읽지 못하면 `inspectionExpired`, 그 밖의 저장 실패는 `storeWriteFailed`.
    /// - Parameter label: 로그에 남길 쓰던 것의 이름(장이면 `label(_:)`).
    static func applyFailure(_ error: any Error, label: String) -> any Error {
        switch error {
        case is CancellationError:
            return error
        case is BackupFormatError, is BackupChapterRestoreError:
            Log.error("불러오기 — 평문 작업 폴더의 blob 을 쓸 수 없어 멈춘다", label, "\(error)")
            return BackupImportError.inspectionExpired
        default:
            Log.error("불러오기 — 이 장을 쓰지 못해 멈춘다(쓴 장은 그대로)", label, "\(error)")
            return BackupImportError.storeWriteFailed
        }
    }
}

/// 적용이 장을 쓰지 않고 멈춘 까닭.
enum BackupImportStop: Equatable {
    /// 쓰기 게이트가 막혔다.
    case blocked(SyncedWriteBlock)
    /// 저장소 소유가 대상 계정과 다르거나 서버 작업 표가 무효다.
    case accountChanged
    /// 적용 중 저장소 세대가 바뀌었다(「모든 필사 삭제」).
    case generationChanged
}
