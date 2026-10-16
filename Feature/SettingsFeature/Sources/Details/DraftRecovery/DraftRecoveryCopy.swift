//
//  DraftRecoveryCopy.swift
//  SettingsFeature
//
//  「확인이 필요한 필기」 의 문구를 한곳에 둔다 — 같은 사실을 화면마다 다르게 말하지 않게 (2026-09-29).
//  문구는 모듈 카탈로그(`Resources/Localizable.xcstrings`)에 ko · en 으로 두고 `SettingsCatalog` 로 꺼낸다 — 수는 카탈로그 복수형이다(영어 현지화 결정 5 · 8).
//  언어는 부르는 쪽이 넘긴다 — 뷰는 환경 `locale`, 리듀서 · effect 는 만들 때의 `AppLanguage.displayLocale()`(즉시 전환 단계 3).
//

import Domain
import Foundation

public enum DraftRecoveryCopy {
    /// 화면 이름 — 앱이 무엇을 했는지(따로 보관함)가 아니라 **사용자가 왜 봐야 하는지**를 말한다(2026-09-29).
    public static func title(locale: Locale) -> String { SettingsCatalog.string("확인이 필요한 필기", locale: locale) }

    /// 화면 첫 설명 — 무엇이 여기 있고 왜 자동으로 반영하지 않았는가.
    public static func introduction(locale: Locale) -> String {
        SettingsCatalog.string("""
            이 iPad에서 썼지만 현재 필사에 반영됐는지 확인이 필요한 내용이에요. \
            iCloud 계정을 확인하지 못했거나, 같은 절의 저장된 내용이 달라져 자동으로 반영하지 않았어요.
            """, locale: locale)
    }

    /// 화면 첫 설명의 둘째 단락 — 무엇을 하면 되는가.
    public static func guidance(locale: Locale) -> String {
        SettingsCatalog.string("필기가 사라지지 않도록 이 iPad에 따로 남겨 두었어요. 현재 필사와 비교한 뒤 사용할 내용을 선택해 주세요.", locale: locale)
    }

    /// 보관의 뜻 — 백업이 아니다.
    public static func storageNote(locale: Locale) -> String {
        SettingsCatalog.string("""
            여기에 남겨 둔 필기는 다른 기기에서도 볼 수 있는 iCloud 백업을 뜻하지 않아요. \
            앱을 삭제하거나 ‘모든 필사 삭제’를 실행하면 사라질 수 있어요.
            """, locale: locale)
    }

    // MARK: - 요약

    /// 전체 요약 — 남겨 둔 필기 전체와 그중 확인이 필요한 것을 따로 적는다. 같은 수로 뭉뚱그리면 자동으로 표시되는 필기까지 확인해야 할 것처럼 읽힌다.
    public static func totalLine(draftCount: Int, draftBytes: Int64, locale: Locale) -> String {
        SettingsCatalog.string("이 iPad에 남겨 둔 필기 \(draftCount)개 · \(bytesText(draftBytes, locale: locale))", locale: locale)
    }

    public static func pendingLine(_ pending: Int, locale: Locale) -> String {
        pending == 0
            ? SettingsCatalog.string("확인이 필요한 필기는 없어요.", locale: locale)
            : SettingsCatalog.string("그중 확인이 필요한 필기 \(pending)개", locale: locale)
    }

    public static func archivedLine(_ count: Int, locale: Locale) -> String {
        SettingsCatalog.string("보관만 하는 예전 필기 \(count)개", locale: locale)
    }

    /// 대조한 묶음에 확인이 필요한 필기가 없을 때.
    public static func nothingPending(locale: Locale) -> String {
        SettingsCatalog.string("확인이 필요한 필기가 없어요. 남겨 둔 필기는 그 장을 열면 자동으로 표시되거나 이미 현재 필사에 반영돼 있어요.", locale: locale)
    }

    /// 지금 계정에서 열어 보지 않는 묶음 — **수 · 용량만** 말한다(2026-09-21 후속 리뷰 P0-1).
    public static func notOpenedBucket(locale: Locale) -> String {
        SettingsCatalog.string("이 묶음은 지금 계정에서 열어 보지 않아요. 개수와 용량만 보이고, 그 계정으로 돌아오면 자세히 볼 수 있어요. 파일은 그대로 있어요.", locale: locale)
    }

    /// 대조한 묶음 안의, 다른 계정을 참고하던 확인 전 필기.
    public static func otherHintNote(_ count: Int, locale: Locale) -> String {
        SettingsCatalog.string("다른 계정을 쓰던 때의 필기 \(count)개는 여기서 열어 보지 않아요. 그 계정으로 돌아오면 볼 수 있어요. 파일은 그대로 있어요.", locale: locale)
    }

    /// 전체 요약에 덧붙이는 한 줄 — 분류하지 않은 수는 따로 말한다.
    public static func unopenedLine(_ count: Int, locale: Locale) -> String {
        SettingsCatalog.string("지금 계정에서 열어 보지 않은 필기 \(count)개는 분류하지 않았어요.", locale: locale)
    }

    /// 묶음 카드 한 줄. **분류한 적 없는 수를 "확인이 필요한 필기" 라 부르지 않는다**(P0-1) — 지금 계정에서 열어 보지 않는 묶음은 수 · 용량만 말한다.
    public static func bucketDetail(_ bucket: DraftRecoveryFeature.Bucket, locale: Locale) -> String {
        if bucket.readFailed { return SettingsCatalog.string("읽지 못했어요 · 파일은 그대로 있어요", locale: locale) }
        var parts = [SettingsCatalog.string("필기 \(bucket.draftCount)개 · \(bytesText(bucket.draftBytes, locale: locale))", locale: locale)]
        if bucket.unreadableCount > 0 { parts.append(SettingsCatalog.string("읽지 못한 파일 \(bucket.unreadableCount)개", locale: locale)) }
        guard bucket.comparedWithStore else {
            parts.append(SettingsCatalog.string("지금 계정에서는 열어 보지 않아요", locale: locale))
            return parts.joined(separator: " · ")
        }
        let pending = bucket.pendingItems.count
        parts.append(
            pending == 0
                ? SettingsCatalog.string("확인이 필요한 필기 없음", locale: locale)
                : SettingsCatalog.string("확인이 필요한 필기 \(pending)개", locale: locale)
        )
        if !bucket.archivedItems.isEmpty { parts.append(archivedLine(bucket.archivedItems.count, locale: locale)) }
        if bucket.inaccessibleCount > 0 {
            parts.append(SettingsCatalog.string("다른 계정을 쓰던 때의 필기 \(bucket.inaccessibleCount)개", locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    /// 묶음 이름. **로그인하지 않은 동안 · 계정을 확인하지 못한 동안을 먼저 가린다** — 로그아웃 상태에서는 이 기기 전용 묶음이
    /// "지금 근거의 묶음" 이라 「지금 계정」 으로 읽히는데, 그때는 계정이 없다(2026-09-21 기기 확인).
    public static func bucketTitle(_ scope: AccountScope, environment: DrawingEditEnvironment, locale: Locale) -> String {
        switch scope {
        case .unverified: return SettingsCatalog.string("계정을 확인하지 못한 동안", locale: locale)
        case .localOnly: return SettingsCatalog.string("로그인하지 않은 동안", locale: locale)
        default:
            guard scope != environment.accountBasis.preservationScope else { return SettingsCatalog.string("지금 계정", locale: locale) }
            let suffix = String(scope.key.suffix(6))
            return SettingsCatalog.string("다른 계정 · \(suffix)", locale: locale)
        }
    }

    /// 그때의 계정 근거 한 줄. **귀속을 올리지 않는다** — 다른 근거의 필기를 지금 계정의 것처럼 쓰지 않는다.
    public static func provenance(of draft: VerseDraft, environment: DrawingEditEnvironment, locale: Locale) -> String {
        let reference = environment.accountBasis.referencedAccount
        var text: String
        switch draft.account {
        case .confirmed(let token):
            text = token.scope == reference
                ? SettingsCatalog.string("이 계정에서 씀", locale: locale)
                : SettingsCatalog.string("다른 계정에서 씀", locale: locale)
        case .unverified(let hint):
            if hint == nil {
                text = SettingsCatalog.string("계정을 확인하기 전에 씀", locale: locale)
            } else {
                text = hint == reference
                    ? SettingsCatalog.string("계정을 확인하기 전에 씀 · 이 계정을 참고", locale: locale)
                    : SettingsCatalog.string("계정을 확인하기 전에 씀 · 다른 계정을 참고", locale: locale)
            }
        case .localOnly:
            text = SettingsCatalog.string("iCloud에 로그인하지 않고 씀", locale: locale)
        }
        // K 를 읽지 못한 채 쓴 필기는 알려진 삭제보다 앞인지 가릴 수 없다 — 그 사실을 숨기지 않는다.
        if draft.knownEpochs == nil { text += " · " + SettingsCatalog.string("삭제 기록 기준을 모름", locale: locale) }
        return text
    }

    // MARK: - 항목마다의 까닭 — 그 항목에 해당하는 이유만 보인다

    public static func reasonTitle(_ reason: VerseDraftRecoveryReason, locale: Locale) -> String {
        switch reason {
        case .beforeConnection: SettingsCatalog.string("iCloud 연결 전에 쓴 필기", locale: locale)
        case .storeMoved: SettingsCatalog.string("현재 필사와 내용이 달라요", locale: locale)
        case .recoverable: SettingsCatalog.string("iCloud에 반영되지 않은 수정", locale: locale)
        case .uncertain: SettingsCatalog.string("저장됐는지 확인하지 못한 필기", locale: locale)
        case .otherBasis: SettingsCatalog.string("삭제 기록을 확인하지 못한 필기", locale: locale)
        case .newerDraftShown: SettingsCatalog.string("같은 절에 더 늦게 쓴 필기가 있어요", locale: locale)
        case .undisplayable: SettingsCatalog.string("위치 정보를 읽지 못한 필기", locale: locale)
        case .savedEarlier: SettingsCatalog.string("예전에 저장한 필기", locale: locale)
        case .inHistory: SettingsCatalog.string("이미 저장된 필기", locale: locale)
        }
    }

    public static func reasonDetail(_ reason: VerseDraftRecoveryReason, locale: Locale) -> String {
        switch reason {
        case .beforeConnection:
            SettingsCatalog.string("""
                이 필기를 쓸 때는 iCloud 계정을 확인할 수 없었어요. 어느 계정의 필사에 넣어야 할지 확인하지 못해 이 iPad에 따로 저장했어요. \
                현재 필사에 자동으로 반영하지 않았으니, 내용을 확인한 뒤 넣어 주세요.
                """, locale: locale)
        case .storeMoved:
            SettingsCatalog.string("""
                이 필기를 쓴 뒤 같은 절에 저장된 내용이 바뀌었어요. 현재 내용을 덮어쓰지 않도록 이 필기를 따로 남겨 두었어요. \
                두 내용을 비교해 사용할 필기를 선택해 주세요.
                """, locale: locale)
        case .recoverable:
            SettingsCatalog.string("""
                같은 절이 이 필기보다 앞서 저장한 내용으로 돌아왔어요. 그 뒤에 고친 이 필기는 이 iPad에만 있어요. \
                현재 필사와 비교해 사용할 필기를 선택해 주세요.
                """, locale: locale)
        case .uncertain:
            SettingsCatalog.string("""
                저장하던 중에 앱이 종료됐고, 그 뒤 같은 절의 내용이 바뀌었어요. 이 필기가 저장됐는지 확인할 수 없어 따로 남겨 두었어요. \
                현재 필사와 비교해 사용할 필기를 선택해 주세요.
                """, locale: locale)
        case .otherBasis:
            SettingsCatalog.string(
                "이 필기를 쓸 때와 지금의 삭제 기록 기준이 달라 자동으로 반영하지 않았어요. 지웠던 내용이 다시 들어가지 않는지 확인한 뒤 넣어 주세요.",
                locale: locale
            )
        case .newerDraftShown:
            SettingsCatalog.string("같은 절에 이 iPad에서 더 늦게 쓴 필기가 있어 그쪽을 보여 주고 있어요. 이 필기도 지우지 않고 남겨 두었어요.", locale: locale)
        case .undisplayable:
            SettingsCatalog.string(
                "이 필기를 놓을 위치 정보를 읽지 못해 현재 필사에 넣을 수 없어요. 미리보기로 내용만 확인할 수 있고, 필기는 이 iPad에 그대로 남아 있어요.",
                locale: locale
            )
        case .savedEarlier:
            SettingsCatalog.string("저장을 마친 뒤 같은 절을 이어서 고친 예전 필기예요. 확인할 필요는 없지만 지우지 않고 남겨 두었어요.", locale: locale)
        case .inHistory:
            SettingsCatalog.string("같은 내용이 현재 필사나 「이전 필사 내용 보기」에 이미 있어요. 확인할 필요는 없지만 지우지 않고 남겨 두었어요.", locale: locale)
        }
    }

    // MARK: - 견주기와 넣기

    /// 넣기 버튼. 바꾸기면 지금 필기가 어디에 남는지 따로 적는다(`replaceNote`).
    public static func actionTitle(_ action: VerseDraftImportCheck.Action, locale: Locale) -> String? {
        switch action {
        case .insert: SettingsCatalog.string("이 필기를 현재 필사에 넣기", locale: locale)
        case .replace: SettingsCatalog.string("이 필기로 바꾸기", locale: locale)
        case .alreadyApplied, .unavailable: nil
        }
    }

    public static func replaceNote(locale: Locale) -> String {
        SettingsCatalog.string("바꿔도 현재 필기는 지우지 않아요. 「이전 필사 내용 보기」에 남아 다시 고를 수 있어요.", locale: locale)
    }
    public static func alreadyAppliedNote(locale: Locale) -> String { SettingsCatalog.string("이미 반영된 필기예요.", locale: locale) }
    public static func unavailableNote(locale: Locale) -> String {
        SettingsCatalog.string("위치 정보를 읽지 못해 현재 필사에 넣을 수 없어요. 필기는 이 iPad에 그대로 남아 있어요.", locale: locale)
    }
    public static func laterTitle(locale: Locale) -> String { SettingsCatalog.string("나중에 확인하기", locale: locale) }

    /// 지웠던 내용이 다시 들어갈 수 있을 때 묻는 문구.
    public static func caution(_ caution: VerseDraftImportCheck.Caution, locale: Locale) -> String {
        switch caution {
        case .verseClearedAfterDraft:
            SettingsCatalog.string("이 필기를 쓴 뒤 이 절이 지워졌어요. 넣으면 지웠던 절에 필기가 다시 들어가요.", locale: locale)
        case .eraseAfterDraft:
            SettingsCatalog.string("이 필기를 쓴 뒤 ‘모든 필사 삭제’가 있었어요. 넣으면 지웠던 내용이 다시 들어갈 수 있어요.", locale: locale)
        case .eraseHistoryUnknown:
            SettingsCatalog.string("삭제 기록을 확인하지 못했어요. 넣으면 지웠던 내용이 다시 들어갈 수 있어요.", locale: locale)
        }
    }

    public static func cautionConfirmTitle(_ action: VerseDraftImportCheck.Action, locale: Locale) -> String {
        action == .replace ? SettingsCatalog.string("그래도 바꾸기", locale: locale) : SettingsCatalog.string("그래도 넣기", locale: locale)
    }

    /// 지금 넣을 수 없는 까닭 — 목록 위에 한 번 적고 버튼을 막는다. 내용은 확인하고 비교할 수 있다.
    public static func importBlocked(_ block: SyncedWriteBlock, locale: Locale) -> String {
        let reason = switch block {
        case .signedOut: SettingsCatalog.string("iCloud에 로그인하지 않았어요. 로그인한 뒤 앱을 다시 열면 넣을 수 있어요.", locale: locale)
        case .accountUnconfirmed: SettingsCatalog.string("iCloud 계정을 확인하는 중이에요. 확인이 끝나면 넣을 수 있어요.", locale: locale)
        case .ownershipUnverified: SettingsCatalog.string("이 iPad의 필사가 지금 iCloud 계정의 것인지 아직 확인하지 못했어요.", locale: locale)
        case .knowledgeUnreadable: SettingsCatalog.string("삭제 기록을 읽지 못했어요. 앱을 다시 열어 보세요.", locale: locale)
        case .verseFromOtherSession: SettingsCatalog.string("다른 계정을 쓰던 때의 필기라 지금 계정에 넣지 않아요.", locale: locale)
        case .connectionHeld: SettingsCatalog.string("iCloud 연결을 마치려면 앱을 다시 열어 주세요.", locale: locale)
        }
        return SettingsCatalog.string("지금은 현재 필사에 넣을 수 없어요. \(reason) 내용은 확인하고 비교할 수 있어요.", locale: locale)
    }

    // MARK: - 넣은 뒤 — 저장을 마친 뒤에만 완료를 말한다

    public static func imported(_ place: String, previousKept: Bool, locale: Locale) -> String {
        previousKept
            ? SettingsCatalog.string("\(place)의 필기를 이 필기로 바꿨어요. 이전 필기는 「이전 필사 내용 보기」에 남아 있어요.", locale: locale)
            : SettingsCatalog.string("\(place)에 이 필기를 넣었어요.", locale: locale)
    }

    public static func alreadyApplied(_ place: String, locale: Locale) -> String {
        SettingsCatalog.string("\(place)의 현재 필사가 이미 이 필기와 같아요.", locale: locale)
    }

    public static func currentChanged(locale: Locale) -> String {
        SettingsCatalog.string("비교하는 사이 현재 필기가 바뀌었어요. 다시 비교한 내용을 확인해 주세요.", locale: locale)
    }
    public static func draftChanged(locale: Locale) -> String {
        SettingsCatalog.string("남겨 둔 필기가 그 사이 바뀌었어요. 목록을 다시 읽었으니 다시 확인해 주세요.", locale: locale)
    }
    public static func importUnavailable(locale: Locale) -> String {
        SettingsCatalog.string("위치 정보를 읽지 못해 현재 필사에 넣지 못했어요. 필기는 그대로 남아 있어요.", locale: locale)
    }
    public static func importFailed(locale: Locale) -> String {
        SettingsCatalog.string("넣지 못했어요. 현재 필사와 남겨 둔 필기는 그대로예요. 다시 시도해 주세요.", locale: locale)
    }

    // MARK: - 필사책 (2.2 회차별 필사책)

    /// 기본이 아닌 필사책의 이름 — 사용자가 붙인 이름 그대로다(옮기지 않는다). 이름이 없으면(필사책 정보에 이름이 없거나 목록에 없는 필사책 —
    /// 지운 필사책의 늦게 온 필기 · 정보보다 먼저 온 필기) 화면 언어의 「이름 없는 필사책」 이다. 숨기거나 기본 필사책에 합치지 않는다(혼재 버전 규칙 ⑥).
    /// 공백뿐인 이름도 이름이 없는 것으로 본다.
    /// - Parameters:
    ///   - storedName: 필사책 정보의 이름(`NotebookSnapshot.name`). 목록에 없으면 nil.
    ///   - locale: 문구 언어 — 리듀서 · effect 는 만들 때의 `AppLanguage.displayLocale()`.
    public static func notebookName(storedName: String?, locale: Locale) -> String {
        if let storedName, !storedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return storedName }
        return SettingsCatalog.string("이름 없는 필사책", locale: locale)
    }

    /// 자리 — 기본 필사책이 아니면 앞에 필사책 이름을 붙인다(「아침 필사 · 창세기 1장 3절 · KJV」). 기본 필사책은 `place(_:locale:)` 그대로다 —
    /// 2.2 이전의 모든 필사가 기본 필사책이라 지금까지와 같게 보인다.
    /// - Parameter notebookNames: 이름이 있는 필사책의 이름(`NotebookSnapshot.name`). 여기 없는 필사책은 「이름 없는 필사책」.
    public static func place(_ key: VerseDraftKey, notebookNames: [NotebookID: String], locale: Locale) -> String {
        withNotebook(key.notebook, place(key, locale: locale), notebookNames: notebookNames, locale: locale)
    }

    /// 읽지 못한 장 이름 — 자리와 같이 기본 필사책이 아니면 앞에 필사책 이름을 붙인다(「아침 필사 · 창세기 1장」).
    public static func chapterName(_ page: NotebookChapter, notebookNames: [NotebookID: String], locale: Locale) -> String {
        withNotebook(page.notebook, chapterName(page.chapter, locale: locale), notebookNames: notebookNames, locale: locale)
    }

    /// 기본이 아닌 필사책이면 문구 앞에 필사책 이름을 붙인다.
    private static func withNotebook(_ notebook: NotebookID, _ text: String, notebookNames: [NotebookID: String], locale: Locale) -> String {
        guard !notebook.isDefault else { return text }
        return notebookName(storedName: notebookNames[notebook], locale: locale) + " · " + text
    }

    // MARK: - 형식

    /// 「창세기 1장 3절 · KJV」 · 「창세기 1장 3절」 — 번역본이 섞이는 목록이라 KJV · BSB 는 약칭을 붙이고,
    /// 개역개정은 생략한다(영어 현지화 결정 11 · 사용자 결정 17, `chapterName`). 필사책 이름은 붙이지 않는다 — 목록의 줄은 `place(_:notebookNames:locale:)`.
    /// 권 · 번역본을 이 판이 모르면(모르는 원본 이름) 그 값을 그대로 보인다 — 어디인지 숨기지 않는다.
    public static func place(_ key: VerseDraftKey, locale: Locale) -> String {
        guard let chapter = key.bibleChapter else {
            return "\(key.title) \(key.chapter):\(key.verse) · \(key.translation)"
        }
        return reference(chapter, verses: .verse(key.verse), locale: locale)
    }

    /// 읽지 못한 장 이름(「창세기 1장 · KJV」 · 「창세기 1장」) — 자리 표기와 같은 약칭 규칙이다(사용자 결정 17).
    /// 필사책 이름은 붙이지 않는다 — 목록은 `chapterName(_:notebookNames:locale:)`.
    public static func chapterName(_ chapter: BibleChapter, locale: Locale) -> String {
        reference(chapter, verses: .wholeChapter, locale: locale)
    }

    /// 확인이 필요한 필기의 참조 — KJV · BSB 만 약칭을 붙인다(사용자 결정 17 — 2.0 까지 개역개정만 있던 목록의 표기를 그대로 둔다).
    private static func reference(_ chapter: BibleChapter, verses: BibleReference.Verses, locale: Locale) -> String {
        BibleReference(chapter: chapter, verses: verses, showsTranslation: chapter.translation != .NKRV)
            .text(locale: locale)
    }

    /// 쓴 때 · 바뀐 때 — 넘긴 로케일의 날짜 · 시각(ko 「2026년 10월 6일 오후 9:05」, en 「Oct 6, 2026 at 9:05 PM」).
    public static func dateText(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
    }

    /// 용량 — 넘긴 로케일의 파일 크기 서식.
    public static func bytesText(_ bytes: Int64, locale: Locale) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }
}
