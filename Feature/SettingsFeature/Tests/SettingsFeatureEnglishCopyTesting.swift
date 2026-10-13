//
//  SettingsFeatureEnglishCopyTesting.swift
//  SettingsFeatureTest
//
//  설정 화면 문구의 영어(영어 현지화 결정 5 · 6 · 8) — 백업 결과 · 확인이 필요한 필기 날짜 · 복수형.
//  리듀서가 만드는 문구는 만드는 순간의 화면 언어(`AppLanguage.displayLocale()`)를 따른다(즉시 전환 단계 3).
//

@testable import SettingsFeature
import ClientInterfaces
import Domain
import Foundation
import Testing

import ComposableArchitecture

/// 시험은 ko-KR 로 돈다(결정 6). 영어는 문구 함수에 `Locale(identifier: "en")` 을 넘겨 언어를 실제로 고르는 경로(`LocalizedStringResource`)로 본다.
///
/// 이 파일이 막는 것:
/// - 영어 기기에서 문구가 한국어 원문으로 남는 것(카탈로그 키가 코드와 어긋나거나 영어가 빠진 것)
/// - 수에 따라 단 · 복수가 바뀌지 않는 것(「1 drafts」), 여러 수가 든 문구의 순서가 섞이는 것
/// - 고정 ko_KR 날짜 서식이 영어 기기에 남는 것
/// - 앱 안에서 언어를 골랐는데 리듀서가 만드는 문구(대화상자 · 결과 한 줄)가 시작 때 언어로 남는 것
@Suite("설정 — 영어 문구")
@MainActor
struct SettingsFeatureEnglishCopyTesting {
    private static let englishLocale = Locale(identifier: "en")
    private typealias Import = BackupImportFeature

    /// 한글이 섞였는가 — 영어 문구에 한국어 원문이 남았는지 본다.
    private func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    // MARK: - 백업 결과

    @Test("불러오기 결과 — 다 넣었는가 · 멈춘 까닭과 넣은 장 수를 영어로 말한다")
    func importResultTitles() {
        let tally = Import.Tally(new: 2, same: 3, archived: 4, protectedCleared: 1, skippedEmpty: 1, unsupported: 2)
        let english = Self.englishLocale

        #expect(BackupCopy.resultTitle(.completed(tally), locale: english) == "Import finished.")
        #expect(BackupCopy.resultTitle(.completed(Import.Tally(same: 1)), locale: english) == "Import finished. No new writing was added.")
        #expect(BackupCopy.resultTitle(.blocked(.signedOut, doneChapters: 2, tally: tally), locale: english)
            == "Import stopped. Sign in to iCloud and reopen the app to import. The 2 chapters already added stay as they are.")
        #expect(BackupCopy.resultTitle(.blocked(.connectionHeld, doneChapters: 1, tally: tally), locale: english)
            == "Import stopped. Sign in to iCloud and reopen the app to import. The 1 chapter already added stays as it is.")
        #expect(BackupCopy.resultTitle(.accountChanged(doneChapters: 1, tally: tally), locale: english)
            == "Import stopped because your iCloud account changed. The 1 chapter already added stays as it is.")
        #expect(BackupCopy.resultTitle(.accountChanged(doneChapters: 3, tally: tally), locale: english)
            == "Import stopped because your iCloud account changed. The 3 chapters already added stay as they are.")
        #expect(BackupCopy.resultTitle(.generationChanged(tally: tally), locale: english).hasPrefix("Stopped because all writing was deleted while adding."))
    }

    @Test("불러오기 결과의 수 — 여러 수가 제자리에 들어가고 첫 수에 따라 단 · 복수가 바뀐다")
    func importTallyLines() {
        let many = Import.Tally(new: 2, same: 3, archived: 4, protectedCleared: 1, skippedEmpty: 1, unsupported: 2)
        let one = Import.Tally(new: 1)
        let english = Self.englishLocale

        #expect(BackupCopy.insertedLine(many, locale: english) == "7 writing entries added — new 2 · history 4 · history only (cleared verse) 1")
        #expect(BackupCopy.insertedLine(one, locale: english) == "1 writing entry added — new 1 · history 0 · history only (cleared verse) 0")
        #expect(BackupCopy.skippedLine(many, locale: english) == "4 skipped — same 3 · empty records 1")
        #expect(BackupCopy.notInsertedLine(1, locale: english) == "1 not added — this app can't read it")
        #expect(BackupCopy.notInsertedLine(2, locale: english) == "2 not added — this app can't read them")
        #expect(BackupCopy.savedLocally(locale: english) == "Saved on this device. Sending to iCloud happens separately.")
    }

    @Test("백업 만들기 결과 · 진행 — 담은 수와 장 수를 영어 복수형으로 말한다")
    func exportLines() {
        let english = Self.englishLocale

        #expect(BackupCopy.saved(rows: 1, drafts: 3, locale: english) == "Backup saved with 1 writing entry and 3 kept drafts.")
        #expect(BackupCopy.saved(rows: 12, drafts: 1, locale: english) == "Backup saved with 12 writing entries and 1 kept draft.")
        #expect(BackupCopy.exporting(BackupExportFeature.ExportProgress(done: 3, total: 10), locale: english) == "Collecting writing · 3 of 10 chapters")
        #expect(BackupCopy.exporting(BackupExportFeature.ExportProgress(done: 0, total: 1), locale: english) == "Collecting writing · 0 of 1 chapter")
        #expect(BackupCopy.exporting(nil, locale: english) == "Creating the backup file…")
        #expect(BackupCopy.passwordIssue(.tooShort, locale: english) == "The password must be at least 8 characters.")
        #expect(BackupCopy.passwordWarning(locale: english) == "If you forget the password, even Carve can't open this file.")
    }

    @Test("멈춘 불러오기 진행 — 인자 순서가 바뀌어도(전체 · 넣은 장 · 넣은 필사) 제자리에 든다")
    func pendingJobProgressOrder() {
        let job = ImportFixture.job(canResume: true)
        let english = Self.englishLocale

        #expect(BackupCopy.pendingJobProgress(job, locale: english) == "Added 1 of 3 chapters · 3 writing entries added")
        #expect(BackupCopy.resumedChapters(1, locale: english) == "Skips the 1 chapter already added and adds the rest.")
        #expect(BackupCopy.resumedChapters(2, locale: english) == "Skips the 2 chapters already added and adds the rest.")
    }

    // MARK: - 확인이 필요한 필기

    @Test("쓴 때 · 바뀐 때 — 고정 ko_KR 이 아니라 로케일 서식이다")
    func draftDateFollowsLocale() {
        // 2026-10-15 12:00 UTC — 어느 시간대에서도 10월이다.
        let date = Date(timeIntervalSince1970: 1_792_065_600)

        let english = DraftRecoveryCopy.dateText(date, locale: Self.englishLocale)
        #expect(english == date.formatted(.dateTime.year().month().day().hour().minute().locale(Self.englishLocale)))
        #expect(english.contains("Oct") && english.contains("2026"))
        #expect(!containsHangul(english))

        // 백업 한 줄도 같은 서식을 쓴다 — 만든 때 · 담은 수(단 · 복수).
        let manifest = BackupManifest(
            backupID: "backup", createdAt: date, appVersion: "2.1.0", scope: BackupScope(rows: true, drafts: true),
            counts: BackupCounts(rows: 1, drafts: 2, blobs: 0), blobs: []
        )
        let summary = BackupCopy.backupSummary(manifest, locale: Self.englishLocale)
        #expect(summary == "Backup from \(english) · 1 writing entry · 2 kept drafts")

        let korean = DraftRecoveryCopy.dateText(date, locale: Locale(identifier: "ko_KR"))
        #expect(korean.contains("2026년 10월"))
    }

    @Test("남겨 둔 필기의 수 — 1 이면 단수, 그 밖은 복수")
    func draftCountsPluralize() {
        let english = Self.englishLocale

        #expect(DraftRecoveryCopy.totalLine(draftCount: 1, draftBytes: 0, locale: english).hasPrefix("1 draft kept on this iPad · "))
        #expect(DraftRecoveryCopy.totalLine(draftCount: 3, draftBytes: 0, locale: english).hasPrefix("3 drafts kept on this iPad · "))
        #expect(DraftRecoveryCopy.pendingLine(0, locale: english) == "No drafts need review.")
        #expect(DraftRecoveryCopy.pendingLine(1, locale: english) == "1 of them needs review")
        #expect(DraftRecoveryCopy.pendingLine(2, locale: english) == "2 of them need review")
        #expect(DraftRecoveryCopy.archivedLine(1, locale: english) == "1 older draft kept for reference")
        #expect(DraftRecoveryCopy.archivedLine(5, locale: english) == "5 older drafts kept for reference")
        #expect(CloudSettingsFeature.eraseConfirmBody(remainingDrafts: 1, locale: english).contains("The 1 draft kept on this iPad will also be deleted"))
        #expect(CloudSettingsFeature.eraseConfirmBody(remainingDrafts: 13, locale: english).contains("All 13 drafts kept on this iPad will also be deleted"))
    }

    @Test("자리 — 영어 기기도 KJV 필기는 「Genesis 1:3 · KJV」, 개역개정 필기는 약칭 없이 「Genesis 1:3」 이다(사용자 결정 17)")
    func draftPlaceUsesEnglishReference() {
        let kjv = VerseDraftKey(sessionID: "s", chapter: BibleChapter(title: .genesis, chapter: 1, translation: .KJV), verse: 3)
        let nkrv = VerseDraftKey(sessionID: "s", chapter: BibleChapter(title: .genesis, chapter: 1), verse: 3)
        let english = Self.englishLocale

        #expect(DraftRecoveryCopy.place(kjv, locale: english) == "Genesis 1:3 · KJV")
        #expect(DraftRecoveryCopy.place(nkrv, locale: english) == "Genesis 1:3")
        #expect(DraftRecoveryCopy.chapterName(BibleChapter(title: .genesis, chapter: 1, translation: .KJV), locale: english) == "Genesis 1 · KJV")
        #expect(DraftRecoveryCopy.chapterName(BibleChapter(title: .genesis, chapter: 1), locale: english) == "Genesis 1")
        #expect(DraftRecoveryCopy.imported("Genesis 1:3 · KJV", previousKept: false, locale: english) == "Added this draft to Genesis 1:3 · KJV.")
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
        let english = Self.englishLocale
        let mailPopup = SendFeedbackFeature.mailUnavailablePopup(locale: english)

        var texts: [String] = [
            DraftRecoveryCopy.title(locale: english), DraftRecoveryCopy.introduction(locale: english),
            DraftRecoveryCopy.guidance(locale: english), DraftRecoveryCopy.storageNote(locale: english),
            DraftRecoveryCopy.nothingPending(locale: english), DraftRecoveryCopy.notOpenedBucket(locale: english),
            DraftRecoveryCopy.otherHintNote(2, locale: english), DraftRecoveryCopy.unopenedLine(1, locale: english),
            DraftRecoveryCopy.replaceNote(locale: english), DraftRecoveryCopy.alreadyAppliedNote(locale: english),
            DraftRecoveryCopy.unavailableNote(locale: english), DraftRecoveryCopy.laterTitle(locale: english),
            DraftRecoveryCopy.currentChanged(locale: english), DraftRecoveryCopy.draftChanged(locale: english),
            DraftRecoveryCopy.importUnavailable(locale: english), DraftRecoveryCopy.importFailed(locale: english),
            DraftRecoveryCopy.alreadyApplied("Genesis 1:1", locale: english),
            DraftRecoveryCopy.cautionConfirmTitle(.insert, locale: english), DraftRecoveryCopy.cautionConfirmTitle(.replace, locale: english),
            DraftRecoveryCopy.caution(.verseClearedAfterDraft, locale: english), DraftRecoveryCopy.caution(.eraseAfterDraft, locale: english),
            DraftRecoveryCopy.caution(.eraseHistoryUnknown, locale: english),
            BackupCopy.title(locale: english), BackupCopy.exportScope(locale: english), BackupCopy.importGuidance(locale: english),
            BackupCopy.exportTitle(locale: english), BackupCopy.exportDescription(locale: english),
            BackupCopy.purchaseRequired(locale: english), BackupCopy.importDescription(locale: english),
            BackupCopy.flushBlocked(locale: english), BackupCopy.chooseFilePrompt(locale: english),
            BackupCopy.previewNote(locale: english), BackupCopy.discardJobNote(locale: english),
            BackupCopy.savedProviderNote(locale: english), BackupCopy.saveFailed(locale: english),
            BackupCopy.unsupportedDetail([.unknownTranslation: 1, .unknownBook: 2], locale: english),
            BackupCopy.pendingJobTitle(ImportFixture.job(canResume: true), locale: english),
            BackupCopy.pendingJobGuidance(ImportFixture.job(canResume: true), locale: english),
            BackupCopy.previewOnly(nil, locale: english), BackupCopy.applying(Import.ApplyProgress(done: 1, total: 3), locale: english),
            CloudSettingsFeature.eraseHeldBody(locale: english), CloudSettingsFeature.eraseConfirmBody(remainingDrafts: nil, locale: english),
            CloudSettingsFeature.holdCopy(hold, availability: .noAccount, connectsOnRelaunch: false, locale: english).title,
            CloudSettingsFeature.holdCopy(hold, availability: .noAccount, connectsOnRelaunch: false, locale: english).detail,
            CloudSettingsFeature.holdCopy(hold, availability: .available, connectsOnRelaunch: true, locale: english).detail,
            CloudSettingsFeature.relaunchToConnect(locale: english),
            CloudSettingsFeature.eraseFailureBody(outcome: .failed, widgetCleared: false, locale: english),
            CloudSettingsFeature.eraseFailureBody(outcome: .partiallyFailed, widgetCleared: true, locale: english),
            mailPopup.title ?? "", mailPopup.body, mailPopup.hint ?? "", mailPopup.confirmTitle,
            SendFeedbackFeature.Requirement.title.hint(locale: english), SendFeedbackFeature.Requirement.body.hint(locale: english),
            SendFeedbackFeature.Requirement.agreements.hint(locale: english)
        ]
        texts += VerseDraftRecoveryReason.allCases.flatMap {
            [DraftRecoveryCopy.reasonTitle($0, locale: english), DraftRecoveryCopy.reasonDetail($0, locale: english)]
        }
        texts += blocks.flatMap { block in
            [
                DraftRecoveryCopy.importBlocked(block, locale: english), BackupCopy.importBlocked(block, locale: english),
                BackupCopy.resultTitle(.blocked(block, doneChapters: 1, tally: tally), locale: english)
            ]
        }
        texts += importFailures.flatMap {
            [BackupCopy.inspectFailed($0, locale: english), BackupCopy.applyFailed($0, locale: english), BackupCopy.retryTitle($0, locale: english)]
        }
        texts += exportFailures.map { BackupCopy.exportFailed($0, locale: english) }
        texts += BackupUnsupportedReason.allCases.map { BackupCopy.unsupportedReason($0, locale: english) }
        texts += UserFeedback.FeedbackType.allCases.map { SendFeedbackFeature.feedbackTypeTitle($0, locale: english) }
        texts += SendFeedbackFeature.AttachmentType.allCases.map { $0.title(locale: english) }
        texts += AppearanceMode.allCases.map { $0.title(locale: english) }
        texts += PatchnoteFeature.releases(locale: english).flatMap { $0.notes.flatMap { [$0.title, $0.body] } }

        let korean = texts.filter(containsHangul)
        #expect(korean.isEmpty, "영어로 옮겨지지 않은 문구: \(korean)")
        let empty = texts.filter(\.isEmpty)
        #expect(empty.isEmpty)
    }

    // MARK: - 리듀서가 만드는 문구 — 만드는 순간의 화면 언어(즉시 전환 단계 3)

    @Test("앱 안에서 언어를 고르지 않으면 리듀서가 얻는 화면 언어는 시험 언어(ko-KR)라 한국어 원문 그대로다 — 기존 한국어 단언의 기준")
    func defaultPathStaysKorean() {
        // Given: 고른 언어를 넣지 않은 저장소 — 리듀서 · effect 가 문구를 만들 때 얻는 locale
        let locale = withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
        } operation: {
            AppLanguage.displayLocale()
        }

        // Then
        #expect(DraftRecoveryCopy.title(locale: locale) == "확인이 필요한 필기")
        #expect(BackupCopy.resultTitle(.completed(Import.Tally(new: 1)), locale: locale) == "불러오기를 마쳤어요.")
        #expect(BackupCopy.passwordWarning(locale: locale) == "암호를 잊으면 새기다 앱도 이 파일을 열 수 없어요.")
    }

    @Test("앱 안에서 영어를 고르면 리듀서가 띄우는 안내도 그 순간부터 영어다 — 다시 시작하지 않는다")
    func reducerPopupFollowsInAppLanguage() {
        // Given: 설정 › 화면 › 언어에서 영어를 고른 저장소, 메일 계정이 없는 기기
        var state = SendFeedbackFeature.State.initialState
        withDependencies {
            $0.defaultInMemoryStorage = InMemoryStorage()
            $0.mailComposeAvailability = MailComposeAvailabilityClient(canSendMail: { false })
        } operation: {
            @Shared(.appLanguageOverride) var languageOverride: AppLanguage?
            $languageOverride.withLock { $0 = .english }

            // When: 보내기를 누른다 — 메일을 보낼 수 없다는 안내를 띄운다
            _ = SendFeedbackFeature().reduce(into: &state, action: .sendFeedback)
        }

        // Then: 안내 대화상자는 띄운 순간의 화면 언어(영어)로 만들어졌다
        #expect(state.path?.popup == SendFeedbackFeature.mailUnavailablePopup(locale: Self.englishLocale))
        #expect(state.path?.popup?.title == "Can't Send Mail")
        #expect(state.path?.popup?.confirmTitle == "OK")
    }
}
