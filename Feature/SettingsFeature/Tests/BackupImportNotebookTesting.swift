//
//  BackupImportNotebookTesting.swift
//  SettingsFeatureTest
//
//  「백업 불러오기」 미리보기의 필사책(2.2 회차별 필사책) — 담긴 필사책 수와 「알 수 없는 필사책」.
//  형식 1(2.1 백업)은 모두 기본 필사책이라 1권, 형식 2 는 항목의 필사책과 필사책 목록을 센 수다(수 자체는 Domain 불러오기가 센다).
//

@testable import SettingsFeature
import Domain
import Foundation
import Testing

import ComposableArchitecture

/// 이 파일이 막는 것:
/// - 형식 1 · 2 백업의 미리보기가 검사 결과의 필사책 수를 보이지 않거나 다른 수를 보이는 것
/// - 필사책 토큰이 깨진 항목(「알 수 없는 필사책」)이 넣을 수 없는 것의 수에는 드는데 사유에는 빠지는 것
/// - 담긴 것이 없는 백업에 「필사책 0권」 을 보이는 것
@Suite("설정 — 필사 백업 · 불러오기 미리보기의 필사책")
@MainActor
struct BackupImportNotebookTesting {
    /// 문구를 꺼내는 언어 — 시험 언어(스킴 ko-KR)와 같은 한국어라 기대 문구는 한국어 원문 그대로다.
    private static let koreanLocale = Locale(identifier: "ko_KR")
    private static let englishLocale = Locale(identifier: "en")
    private typealias Feature = BackupImportFeature

    private static let notebookA = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-0000000000A1")!)
    private static let notebookB = NotebookID.make(uuid: UUID(uuidString: "0F3A1C2D-0000-4000-8000-0000000000B2")!)

    /// 그 형식 버전의 manifest — 형식 2 만 필사책 목록을 담는다.
    private static func manifest(formatVersion: Int, notebooks: [BackupNotebookRecord] = []) -> BackupManifest {
        BackupManifest(
            formatVersion: formatVersion, backupID: "backup", createdAt: BackupTestTime.now, appVersion: formatVersion == 1 ? "2.1.0" : "2.2.0",
            scope: BackupScope(rows: true, drafts: true), counts: BackupCounts(rows: 7, drafts: 0, blobs: 0), blobs: [], notebooks: notebooks
        )
    }

    /// 필사책 목록의 한 레코드.
    private static func record(_ notebook: NotebookID, name: String?) -> BackupNotebookRecord {
        BackupNotebookRecord(
            id: notebook.rawValue, name: name, status: NotebookStatus.active.rawValue, createdAt: BackupTestTime.now, updatedAt: BackupTestTime.now,
            completedAt: nil, kind: "personal", scopeData: nil, linkData: nil
        )
    }

    /// 고른 파일을 암호로 검사해 미리보기까지 간다 — 미리보기 단계가 들고 있는 미리보기를 돌려준다.
    private func previewAfterInspecting(_ inspection: BackupInspection) async -> BackupImportPreview? {
        let log = LockIsolated<[ImportEvent]>([])
        let url = ImportFixture.fileURL
        let store = makeImportStore(
            .at(.password(.file(url)), password: ImportFixture.password),
            importer: StubBackupImporter(log: log, inspection: .success(inspection)),
            log: log
        )
        let held = Feature.Inspection(inspection)

        await store.send(.view(.inspectTapped)) {
            $0.password = ""
            $0.step = .inspecting(.file(url))
        }
        await store.receive(.inspectFinished(.success(held))) {
            $0.step = .preview(held)
        }
        #expect(log.value == [.accessOpened(url), .inspected(url, password: ImportFixture.password), .accessClosed(url)])
        return store.state.heldInspection?.value.preview
    }

    @Test("형식 1 파일(2.1 백업)의 미리보기 — 필사책 목록이 없고 모두 기본 필사책이라 「필사책 1권」 이다")
    func formatOnePreviewShowsOneNotebook() async throws {
        // Given: 2.1 이 만든 백업 — 필사책 목록 없이 기본 필사책의 장들만 든다(불러오기가 센 필사책 수는 1)
        let inspection = BackupInspection(
            jobID: ImportFixture.jobID, targetScope: ImportFixture.account,
            preview: BackupImportPreview(new: 5, same: 2, notebooks: 1, chapters: [ImportFixture.genesis1, ImportFixture.exodus3]),
            manifest: Self.manifest(formatVersion: 1)
        )

        // When
        let preview = try #require(await previewAfterInspecting(inspection))

        // Then
        #expect(BackupCopy.previewNotebooks(preview, locale: Self.koreanLocale) == "필사책 1권이 담겨 있어요.")
        #expect(BackupCopy.previewNotebooks(preview, locale: Self.englishLocale) == "Includes 1 notebook.")
        #expect(preview.unsupportedCount == 0)
        #expect(BackupCopy.unsupportedDetail(preview, locale: Self.koreanLocale).isEmpty)
    }

    @Test("형식 2 파일의 미리보기 — 담긴 필사책 수를 보이고, 필사책 토큰이 깨진 항목은 「알 수 없는 필사책」 으로 넣을 수 없는 것의 맨 앞에 센다")
    func formatTwoPreviewShowsNotebooksAndUnknownNotebook() async throws {
        // Given: 2.2 가 만든 백업 — 기본 · A · B 세 필사책, 필사책 토큰이 깨진 항목 2 · 모르는 권 1
        let pageA = NotebookChapter(notebook: Self.notebookA, chapter: BibleChapter(title: .genesis, chapter: 1))
        let pageB = NotebookChapter(notebook: Self.notebookB, chapter: BibleChapter(title: .genesis, chapter: 1, translation: .KJV))
        let inspection = BackupInspection(
            jobID: ImportFixture.jobID, targetScope: ImportFixture.account,
            preview: BackupImportPreview(
                new: 4, unsupported: [.unknownBook: 1], unknownNotebook: 2, notebooks: 3, chapters: [ImportFixture.genesis1, pageA, pageB]
            ),
            manifest: Self.manifest(
                formatVersion: 2,
                notebooks: [Self.record(.default, name: nil), Self.record(Self.notebookA, name: "아침 필사"), Self.record(Self.notebookB, name: nil)]
            )
        )

        // When
        let preview = try #require(await previewAfterInspecting(inspection))

        // Then
        #expect(BackupCopy.previewNotebooks(preview, locale: Self.koreanLocale) == "필사책 3권이 담겨 있어요.")
        #expect(BackupCopy.previewNotebooks(preview, locale: Self.englishLocale) == "Includes 3 notebooks.")
        // 넣을 수 없는 것의 수에 알 수 없는 필사책이 들고, 사유에도 그 줄이 있다 — 다른 사유보다 먼저 판정하므로 맨 앞이다.
        #expect(preview.unsupportedCount == 3)
        #expect(BackupCopy.unsupportedDetail(preview, locale: Self.koreanLocale) == "알 수 없는 필사책 2 · 모르는 성경 권 1")
        #expect(BackupCopy.unsupportedDetail(preview, locale: Self.englishLocale) == "Unknown notebook 2 · Unknown book 1")
    }

    @Test("담긴 필사책이 없으면(빈 백업) 필사책 줄을 보이지 않고, 알 수 없는 필사책이 없으면 사유는 지금과 같다")
    func emptyBackupHasNoNotebookLine() {
        #expect(BackupCopy.previewNotebooks(BackupImportPreview(), locale: Self.koreanLocale) == nil)
        #expect(BackupCopy.unsupportedDetail(ImportFixture.preview, locale: Self.koreanLocale)
            == BackupCopy.unsupportedDetail(ImportFixture.preview.unsupported, locale: Self.koreanLocale))
        #expect(BackupCopy.unsupportedDetail(BackupImportPreview(unknownNotebook: 1), locale: Self.koreanLocale) == "알 수 없는 필사책 1")
    }
}
