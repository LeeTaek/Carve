//
//  SettingsFeatureEnglishCopyTesting.swift
//  SettingsFeatureTest
//
//  설정 화면 문구의 영어(영어 현지화 결정 5 · 6 · 8) — 백업 결과 · 확인이 필요한 필기 날짜 · 복수형.
//

@testable import SettingsFeature
import ClientInterfaces
import Domain
import Foundation
import Testing

/// 시험은 ko-KR 로 돈다(결정 6). 영어는 `SettingsCatalog.locale` 을 en 으로 고정해 언어를 실제로 고르는 경로(`LocalizedStringResource`)로 본다.
///
/// 이 파일이 막는 것:
/// - 영어 기기에서 문구가 한국어 원문으로 남는 것(카탈로그 키가 코드와 어긋나거나 영어가 빠진 것)
/// - 수에 따라 단 · 복수가 바뀌지 않는 것(「1 drafts」), 여러 수가 든 문구의 순서가 섞이는 것
/// - 고정 ko_KR 날짜 서식이 영어 기기에 남는 것
@Suite("설정 — 영어 문구")
@MainActor
struct SettingsFeatureEnglishCopyTesting {
    private static let englishLocale = Locale(identifier: "en")
    private typealias Import = BackupImportFeature

    /// 역할: 언어를 영어로 고정한 채 문구를 만든다.
    /// 입력 · 출력: 문구를 만드는 클로저 → 그 결과(영어). 부작용: 이 작업(Task) 안에서만 언어를 바꾼다.
    private func inEnglish<Value>(_ body: () -> Value) -> Value {
        SettingsCatalog.$locale.withValue(Self.englishLocale, operation: body)
    }

    /// 한글이 섞였는가 — 영어 문구에 한국어 원문이 남았는지 본다.
    private func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    // MARK: - 백업 결과

    @Test("불러오기 결과 — 다 넣었는가 · 멈춘 까닭과 넣은 장 수를 영어로 말한다")
    func importResultTitles() {
        let tally = Import.Tally(new: 2, same: 3, archived: 4, protectedCleared: 1, skippedEmpty: 1, unsupported: 2)

        inEnglish {
            #expect(BackupCopy.resultTitle(.completed(tally)) == "Import finished.")
            #expect(BackupCopy.resultTitle(.completed(Import.Tally(same: 1))) == "Import finished. No new writing was added.")
            #expect(BackupCopy.resultTitle(.blocked(.signedOut, doneChapters: 2, tally: tally))
                == "Import stopped. Sign in to iCloud and reopen the app to import. The 2 chapters already added stay as they are.")
            #expect(BackupCopy.resultTitle(.blocked(.connectionHeld, doneChapters: 1, tally: tally))
                == "Import stopped. Sign in to iCloud and reopen the app to import. The 1 chapter already added stays as it is.")
            #expect(BackupCopy.resultTitle(.accountChanged(doneChapters: 1, tally: tally))
                == "Import stopped because your iCloud account changed. The 1 chapter already added stays as it is.")
            #expect(BackupCopy.resultTitle(.accountChanged(doneChapters: 3, tally: tally))
                == "Import stopped because your iCloud account changed. The 3 chapters already added stay as they are.")
            #expect(BackupCopy.resultTitle(.generationChanged(tally: tally)).hasPrefix("Stopped because all writing was deleted while adding."))
        }
    }

    @Test("불러오기 결과의 수 — 여러 수가 제자리에 들어가고 첫 수에 따라 단 · 복수가 바뀐다")
    func importTallyLines() {
        let many = Import.Tally(new: 2, same: 3, archived: 4, protectedCleared: 1, skippedEmpty: 1, unsupported: 2)
        let one = Import.Tally(new: 1)

        inEnglish {
            #expect(BackupCopy.insertedLine(many) == "7 writing entries added — new 2 · history 4 · history only (cleared verse) 1")
            #expect(BackupCopy.insertedLine(one) == "1 writing entry added — new 1 · history 0 · history only (cleared verse) 0")
            #expect(BackupCopy.skippedLine(many) == "4 skipped — same 3 · empty records 1")
            #expect(BackupCopy.notInsertedLine(1) == "1 not added — this app can't read it")
            #expect(BackupCopy.notInsertedLine(2) == "2 not added — this app can't read them")
            #expect(BackupCopy.savedLocally == "Saved on this device. Sending to iCloud happens separately.")
        }
    }

    @Test("백업 만들기 결과 · 진행 — 담은 수와 장 수를 영어 복수형으로 말한다")
    func exportLines() {
        inEnglish {
            #expect(BackupCopy.saved(rows: 1, drafts: 3) == "Backup saved with 1 writing entry and 3 kept drafts.")
            #expect(BackupCopy.saved(rows: 12, drafts: 1) == "Backup saved with 12 writing entries and 1 kept draft.")
            #expect(BackupCopy.exporting(BackupExportFeature.ExportProgress(done: 3, total: 10)) == "Collecting writing · 3 of 10 chapters")
            #expect(BackupCopy.exporting(BackupExportFeature.ExportProgress(done: 0, total: 1)) == "Collecting writing · 0 of 1 chapter")
            #expect(BackupCopy.exporting(nil) == "Creating the backup file…")
            #expect(BackupCopy.passwordIssue(.tooShort) == "The password must be at least 8 characters.")
            #expect(BackupCopy.passwordWarning == "If you forget the password, even Carve can't open this file.")
        }
    }

    @Test("멈춘 불러오기 진행 — 인자 순서가 바뀌어도(전체 · 넣은 장 · 넣은 필사) 제자리에 든다")
    func pendingJobProgressOrder() {
        let job = ImportFixture.job(canResume: true)

        inEnglish {
            #expect(BackupCopy.pendingJobProgress(job) == "Added 1 of 3 chapters · 3 writing entries added")
            #expect(BackupCopy.resumedChapters(1) == "Skips the 1 chapter already added and adds the rest.")
            #expect(BackupCopy.resumedChapters(2) == "Skips the 2 chapters already added and adds the rest.")
        }
    }

    // MARK: - 확인이 필요한 필기

    @Test("쓴 때 · 바뀐 때 — 고정 ko_KR 이 아니라 로케일 서식이다")
    func draftDateFollowsLocale() {
        // 2026-10-15 12:00 UTC — 어느 시간대에서도 10월이다.
        let date = Date(timeIntervalSince1970: 1_792_065_600)

        let english = inEnglish { DraftRecoveryCopy.dateText(date) }
        #expect(english == date.formatted(.dateTime.year().month().day().hour().minute().locale(Self.englishLocale)))
        #expect(english.contains("Oct") && english.contains("2026"))
        #expect(!containsHangul(english))

        // 백업 한 줄도 같은 서식을 쓴다 — 만든 때 · 담은 수(단 · 복수).
        let manifest = BackupManifest(
            backupID: "backup", createdAt: date, appVersion: "2.1.0", scope: BackupScope(rows: true, drafts: true),
            counts: BackupCounts(rows: 1, drafts: 2, blobs: 0), blobs: []
        )
        let summary = inEnglish { BackupCopy.backupSummary(manifest) }
        #expect(summary == "Backup from \(english) · 1 writing entry · 2 kept drafts")

        let korean = SettingsCatalog.$locale.withValue(Locale(identifier: "ko_KR")) { DraftRecoveryCopy.dateText(date) }
        #expect(korean.contains("2026년 10월"))
    }

    @Test("남겨 둔 필기의 수 — 1 이면 단수, 그 밖은 복수")
    func draftCountsPluralize() {
        inEnglish {
            #expect(DraftRecoveryCopy.totalLine(draftCount: 1, draftBytes: 0).hasPrefix("1 draft kept on this iPad · "))
            #expect(DraftRecoveryCopy.totalLine(draftCount: 3, draftBytes: 0).hasPrefix("3 drafts kept on this iPad · "))
            #expect(DraftRecoveryCopy.pendingLine(0) == "No drafts need review.")
            #expect(DraftRecoveryCopy.pendingLine(1) == "1 of them needs review")
            #expect(DraftRecoveryCopy.pendingLine(2) == "2 of them need review")
            #expect(DraftRecoveryCopy.archivedLine(1) == "1 older draft kept for reference")
            #expect(DraftRecoveryCopy.archivedLine(5) == "5 older drafts kept for reference")
            #expect(CloudSettingsFeature.eraseConfirmBody(remainingDrafts: 1).contains("The 1 draft kept on this iPad will also be deleted"))
            #expect(CloudSettingsFeature.eraseConfirmBody(remainingDrafts: 13).contains("All 13 drafts kept on this iPad will also be deleted"))
        }
    }

    @Test("자리 — 영어 기기도 KJV 필기는 「Genesis 1:3 · KJV」, 개역개정 필기는 약칭 없이 「Genesis 1:3」 이다(사용자 결정 17)")
    func draftPlaceUsesEnglishReference() {
        let kjv = VerseDraftKey(sessionID: "s", chapter: BibleChapter(title: .genesis, chapter: 1, translation: .KJV), verse: 3)
        let nkrv = VerseDraftKey(sessionID: "s", chapter: BibleChapter(title: .genesis, chapter: 1), verse: 3)

        inEnglish {
            #expect(DraftRecoveryCopy.place(kjv) == "Genesis 1:3 · KJV")
            #expect(DraftRecoveryCopy.place(nkrv) == "Genesis 1:3")
            #expect(DraftRecoveryCopy.chapterName(BibleChapter(title: .genesis, chapter: 1, translation: .KJV)) == "Genesis 1 · KJV")
            #expect(DraftRecoveryCopy.chapterName(BibleChapter(title: .genesis, chapter: 1)) == "Genesis 1")
            #expect(DraftRecoveryCopy.imported("Genesis 1:3 · KJV", previousKept: false) == "Added this draft to Genesis 1:3 · KJV.")
        }
    }

    // MARK: - 한국어가 남지 않는다

    @Test("String 으로 흐르는 설정 문구는 영어 기기에서 한국어가 남지 않는다")
    func noKoreanLeftInEnglish() {
        let tally = Import.Tally(new: 1, same: 1, archived: 1)
        let blocks: [SyncedWriteBlock] = [.signedOut, .accountUnconfirmed, .ownershipUnverified, .knowledgeUnreadable, .verseFromOtherSession, .connectionHeld]
        let importFailures: [Import.ImportFailure] = [
            .fileUnreadable, .wrongPasswordOrDamaged, .unsupportedFormat, .tooLarge, .insufficientSpace, .ioFailed,
            .storeUnreadable, .storeWriteFailed, .inspectionExpired, .jobNotFound, .jobFromOtherAccount, .unavailable
        ]
        let exportFailures: [BackupExportFeature.ExportFailure] = [
            .generationChanged, .accountChanged, .storeUnreadable, .draftsUnreadable, .insufficientSpace, .writeFailed, .verificationFailed, .unavailable
        ]
        let hold = LegacySeparationHold(reason: .unlinkedRowsAwaitSeparation(count: 2), jobID: "job")

        let texts: [String] = inEnglish {
            var texts: [String] = [
                DraftRecoveryCopy.title, DraftRecoveryCopy.introduction, DraftRecoveryCopy.guidance, DraftRecoveryCopy.storageNote,
                DraftRecoveryCopy.nothingPending, DraftRecoveryCopy.notOpenedBucket, DraftRecoveryCopy.otherHintNote(2),
                DraftRecoveryCopy.unopenedLine(1), DraftRecoveryCopy.replaceNote, DraftRecoveryCopy.alreadyAppliedNote,
                DraftRecoveryCopy.unavailableNote, DraftRecoveryCopy.laterTitle, DraftRecoveryCopy.currentChanged, DraftRecoveryCopy.draftChanged,
                DraftRecoveryCopy.importUnavailable, DraftRecoveryCopy.importFailed, DraftRecoveryCopy.alreadyApplied("Genesis 1:1"),
                DraftRecoveryCopy.cautionConfirmTitle(.insert), DraftRecoveryCopy.cautionConfirmTitle(.replace),
                DraftRecoveryCopy.caution(.verseClearedAfterDraft), DraftRecoveryCopy.caution(.eraseAfterDraft), DraftRecoveryCopy.caution(.eraseHistoryUnknown),
                BackupCopy.title, BackupCopy.exportScope, BackupCopy.importGuidance, BackupCopy.exportTitle, BackupCopy.exportDescription,
                BackupCopy.purchaseRequired, BackupCopy.importDescription, BackupCopy.flushBlocked, BackupCopy.chooseFilePrompt,
                BackupCopy.previewNote, BackupCopy.discardJobNote, BackupCopy.savedProviderNote, BackupCopy.saveFailed,
                BackupCopy.unsupportedDetail([.unknownTranslation: 1, .unknownBook: 2]),
                BackupCopy.pendingJobTitle(ImportFixture.job(canResume: true)), BackupCopy.pendingJobGuidance(ImportFixture.job(canResume: true)),
                BackupCopy.previewOnly(nil), BackupCopy.applying(Import.ApplyProgress(done: 1, total: 3)),
                CloudSettingsFeature.eraseHeldBody, CloudSettingsFeature.eraseConfirmBody(remainingDrafts: nil),
                CloudSettingsFeature.holdCopy(hold, availability: .noAccount, connectsOnRelaunch: false).title,
                CloudSettingsFeature.holdCopy(hold, availability: .noAccount, connectsOnRelaunch: false).detail,
                CloudSettingsFeature.holdCopy(hold, availability: .available, connectsOnRelaunch: true).detail,
                CloudSettingsFeature.eraseFailureBody(outcome: .failed, widgetCleared: false),
                CloudSettingsFeature.eraseFailureBody(outcome: .partiallyFailed, widgetCleared: true),
                SendFeedbackFeature.mailUnavailablePopup.title ?? "", SendFeedbackFeature.mailUnavailablePopup.body,
                SendFeedbackFeature.mailUnavailablePopup.hint ?? "", SendFeedbackFeature.mailUnavailablePopup.confirmTitle,
                SendFeedbackFeature.Requirement.title.hint, SendFeedbackFeature.Requirement.body.hint, SendFeedbackFeature.Requirement.agreements.hint
            ]
            texts += VerseDraftRecoveryReason.allCases.flatMap { [DraftRecoveryCopy.reasonTitle($0), DraftRecoveryCopy.reasonDetail($0)] }
            texts += blocks.flatMap { block in
                [DraftRecoveryCopy.importBlocked(block), BackupCopy.importBlocked(block), BackupCopy.resultTitle(.blocked(block, doneChapters: 1, tally: tally))]
            }
            texts += importFailures.flatMap { [BackupCopy.inspectFailed($0), BackupCopy.applyFailed($0), BackupCopy.retryTitle($0)] }
            texts += exportFailures.map { BackupCopy.exportFailed($0) }
            texts += BackupUnsupportedReason.allCases.map { BackupCopy.unsupportedReason($0) }
            texts += UserFeedback.FeedbackType.allCases.map { SendFeedbackFeature.feedbackTypeTitle($0) }
            texts += SendFeedbackFeature.AttachmentType.allCases.map(\.title)
            texts += AppearanceMode.allCases.map(\.title)
            texts += PatchnoteFeature.releases.flatMap { $0.notes.flatMap { [$0.title, $0.body] } }
            return texts
        }

        let korean = texts.filter(containsHangul)
        #expect(korean.isEmpty, "영어로 옮겨지지 않은 문구: \(korean)")
        let empty = texts.filter(\.isEmpty)
        #expect(empty.isEmpty)
    }

    @Test("언어를 고정하지 않으면 한국어 원문 그대로다 — 기존 한국어 단언의 기준")
    func defaultPathStaysKorean() {
        #expect(DraftRecoveryCopy.title == "확인이 필요한 필기")
        #expect(BackupCopy.resultTitle(.completed(Import.Tally(new: 1))) == "불러오기를 마쳤어요.")
        #expect(BackupCopy.passwordWarning == "암호를 잊으면 새기다 앱도 이 파일을 열 수 없어요.")
    }
}
