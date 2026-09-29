//
//  DraftRecoveryCopy.swift
//  SettingsFeature
//
//  「확인이 필요한 필기」 의 문구를 한곳에 둔다 — 같은 사실을 화면마다 다르게 말하지 않게 (2026-09-29).
//

import Domain
import Foundation

public enum DraftRecoveryCopy {
    /// 화면 이름 — 앱이 무엇을 했는지(따로 보관함)가 아니라 **사용자가 왜 봐야 하는지**를 말한다(2026-09-29).
    public static let title = "확인이 필요한 필기"

    /// 화면 첫 설명 — 무엇이 여기 있고 왜 자동으로 반영하지 않았는가.
    public static let introduction = "이 iPad에서 썼지만 현재 필사에 반영됐는지 확인이 필요한 내용이에요. "
        + "iCloud 계정을 확인하지 못했거나, 같은 절의 저장된 내용이 달라져 자동으로 반영하지 않았어요."

    /// 화면 첫 설명의 둘째 단락 — 무엇을 하면 되는가.
    public static let guidance = "필기가 사라지지 않도록 이 iPad에 따로 남겨 두었어요. 현재 필사와 비교한 뒤 사용할 내용을 선택해 주세요."

    /// 보관의 뜻 — 백업이 아니다.
    public static let storageNote = "여기에 남겨 둔 필기는 다른 기기에서도 볼 수 있는 iCloud 백업을 뜻하지 않아요. "
        + "앱을 삭제하거나 ‘모든 필사 삭제’를 실행하면 사라질 수 있어요."

    // MARK: - 요약

    /// 전체 요약 — 남겨 둔 필기 전체와 그중 확인이 필요한 것을 따로 적는다. 같은 수로 뭉뚱그리면 자동으로 표시되는 필기까지 확인해야 할 것처럼 읽힌다.
    public static func totalLine(draftCount: Int, draftBytes: Int64) -> String {
        "이 iPad에 남겨 둔 필기 \(draftCount)개 · \(bytesText(draftBytes))"
    }

    public static func pendingLine(_ pending: Int) -> String {
        pending == 0 ? "확인이 필요한 필기는 없어요." : "그중 확인이 필요한 필기 \(pending)개"
    }

    public static func archivedLine(_ count: Int) -> String {
        "보관만 하는 예전 필기 \(count)개"
    }

    /// 대조한 묶음에 확인이 필요한 필기가 없을 때.
    public static let nothingPending = "확인이 필요한 필기가 없어요. 남겨 둔 필기는 그 장을 열면 자동으로 표시되거나 이미 현재 필사에 반영돼 있어요."

    /// 지금 계정에서 열어 보지 않는 묶음 — **수 · 용량만** 말한다(2026-09-21 후속 리뷰 P0-1).
    public static let notOpenedBucket = "이 묶음은 지금 계정에서 열어 보지 않아요. 개수와 용량만 보이고, 그 계정으로 돌아오면 자세히 볼 수 있어요. 파일은 그대로 있어요."

    /// 대조한 묶음 안의, 다른 계정을 참고하던 확인 전 필기.
    public static func otherHintNote(_ count: Int) -> String {
        "다른 계정을 쓰던 때의 필기 \(count)개는 여기서 열어 보지 않아요. 그 계정으로 돌아오면 볼 수 있어요. 파일은 그대로 있어요."
    }

    /// 전체 요약에 덧붙이는 한 줄 — 분류하지 않은 수는 따로 말한다.
    public static func unopenedLine(_ count: Int) -> String {
        "지금 계정에서 열어 보지 않은 필기 \(count)개는 분류하지 않았어요."
    }

    /// 묶음 카드 한 줄. **분류한 적 없는 수를 "확인이 필요한 필기" 라 부르지 않는다**(P0-1) — 지금 계정에서 열어 보지 않는 묶음은 수 · 용량만 말한다.
    public static func bucketDetail(_ bucket: DraftRecoveryFeature.Bucket) -> String {
        if bucket.readFailed { return "읽지 못했어요 · 파일은 그대로 있어요" }
        var parts = ["필기 \(bucket.draftCount)개 · \(bytesText(bucket.draftBytes))"]
        if bucket.unreadableCount > 0 { parts.append("읽지 못한 파일 \(bucket.unreadableCount)개") }
        guard bucket.comparedWithStore else {
            parts.append("지금 계정에서는 열어 보지 않아요")
            return parts.joined(separator: " · ")
        }
        let pending = bucket.pendingItems.count
        parts.append(pending == 0 ? "확인이 필요한 필기 없음" : "확인이 필요한 필기 \(pending)개")
        if !bucket.archivedItems.isEmpty { parts.append(archivedLine(bucket.archivedItems.count)) }
        if bucket.inaccessibleCount > 0 { parts.append("다른 계정을 쓰던 때의 필기 \(bucket.inaccessibleCount)개") }
        return parts.joined(separator: " · ")
    }

    /// 묶음 이름. **로그인하지 않은 동안 · 계정을 확인하지 못한 동안을 먼저 가린다** — 로그아웃 상태에서는 이 기기 전용 묶음이
    /// "지금 근거의 묶음" 이라 「지금 계정」 으로 읽히는데, 그때는 계정이 없다(2026-09-21 기기 확인).
    public static func bucketTitle(_ scope: AccountScope, environment: DrawingEditEnvironment) -> String {
        switch scope {
        case .unverified: return "계정을 확인하지 못한 동안"
        case .localOnly: return "로그인하지 않은 동안"
        default: return scope == environment.accountBasis.preservationScope ? "지금 계정" : "다른 계정 · \(scope.key.suffix(6))"
        }
    }

    /// 그때의 계정 근거 한 줄. **귀속을 올리지 않는다** — 다른 근거의 필기를 지금 계정의 것처럼 쓰지 않는다.
    public static func provenance(of draft: VerseDraft, environment: DrawingEditEnvironment) -> String {
        let reference = environment.accountBasis.referencedAccount
        var text: String
        switch draft.account {
        case .confirmed(let token):
            text = token.scope == reference ? "이 계정에서 씀" : "다른 계정에서 씀"
        case .unverified(let hint):
            if hint == nil {
                text = "계정을 확인하기 전에 씀"
            } else {
                text = hint == reference ? "계정을 확인하기 전에 씀 · 이 계정을 참고" : "계정을 확인하기 전에 씀 · 다른 계정을 참고"
            }
        case .localOnly:
            text = "iCloud에 로그인하지 않고 씀"
        }
        // K 를 읽지 못한 채 쓴 필기는 알려진 삭제보다 앞인지 가릴 수 없다 — 그 사실을 숨기지 않는다.
        if draft.knownEpochs == nil { text += " · 삭제 기록 기준을 모름" }
        return text
    }

    // MARK: - 항목마다의 까닭 — 그 항목에 해당하는 이유만 보인다

    public static func reasonTitle(_ reason: VerseDraftRecoveryReason) -> String {
        switch reason {
        case .beforeConnection: "iCloud 연결 전에 쓴 필기"
        case .storeMoved: "현재 필사와 내용이 달라요"
        case .recoverable: "iCloud에 반영되지 않은 수정"
        case .uncertain: "저장됐는지 확인하지 못한 필기"
        case .otherBasis: "삭제 기록을 확인하지 못한 필기"
        case .newerDraftShown: "같은 절에 더 늦게 쓴 필기가 있어요"
        case .undisplayable: "위치 정보를 읽지 못한 필기"
        case .savedEarlier: "예전에 저장한 필기"
        case .inHistory: "이미 저장된 필기"
        }
    }

    public static func reasonDetail(_ reason: VerseDraftRecoveryReason) -> String {
        switch reason {
        case .beforeConnection:
            "이 필기를 쓸 때는 iCloud 계정을 확인할 수 없었어요. 어느 계정의 필사에 넣어야 할지 확인하지 못해 이 iPad에 따로 저장했어요. "
                + "현재 필사에 자동으로 반영하지 않았으니, 내용을 확인한 뒤 넣어 주세요."
        case .storeMoved:
            "이 필기를 쓴 뒤 같은 절에 저장된 내용이 바뀌었어요. 현재 내용을 덮어쓰지 않도록 이 필기를 따로 남겨 두었어요. "
                + "두 내용을 비교해 사용할 필기를 선택해 주세요."
        case .recoverable:
            "같은 절이 이 필기보다 앞서 저장한 내용으로 돌아왔어요. 그 뒤에 고친 이 필기는 이 iPad에만 있어요. "
                + "현재 필사와 비교해 사용할 필기를 선택해 주세요."
        case .uncertain:
            "저장하던 중에 앱이 종료됐고, 그 뒤 같은 절의 내용이 바뀌었어요. 이 필기가 저장됐는지 확인할 수 없어 따로 남겨 두었어요. "
                + "현재 필사와 비교해 사용할 필기를 선택해 주세요."
        case .otherBasis:
            "이 필기를 쓸 때와 지금의 삭제 기록 기준이 달라 자동으로 반영하지 않았어요. 지웠던 내용이 다시 들어가지 않는지 확인한 뒤 넣어 주세요."
        case .newerDraftShown:
            "같은 절에 이 iPad에서 더 늦게 쓴 필기가 있어 그쪽을 보여 주고 있어요. 이 필기도 지우지 않고 남겨 두었어요."
        case .undisplayable:
            "이 필기를 놓을 위치 정보를 읽지 못해 현재 필사에 넣을 수 없어요. 미리보기로 내용만 확인할 수 있고, 필기는 이 iPad에 그대로 남아 있어요."
        case .savedEarlier:
            "저장을 마친 뒤 같은 절을 이어서 고친 예전 필기예요. 확인할 필요는 없지만 지우지 않고 남겨 두었어요."
        case .inHistory:
            "같은 내용이 현재 필사나 「이전 필사 내용 보기」에 이미 있어요. 확인할 필요는 없지만 지우지 않고 남겨 두었어요."
        }
    }

    // MARK: - 견주기와 넣기

    /// 넣기 버튼. 바꾸기면 지금 필기가 어디에 남는지 따로 적는다(`replaceNote`).
    public static func actionTitle(_ action: VerseDraftImportCheck.Action) -> String? {
        switch action {
        case .insert: "이 필기를 현재 필사에 넣기"
        case .replace: "이 필기로 바꾸기"
        case .alreadyApplied, .unavailable: nil
        }
    }

    public static let replaceNote = "바꿔도 현재 필기는 지우지 않아요. 「이전 필사 내용 보기」에 남아 다시 고를 수 있어요."
    public static let alreadyAppliedNote = "이미 반영된 필기예요."
    public static let unavailableNote = "위치 정보를 읽지 못해 현재 필사에 넣을 수 없어요. 필기는 이 iPad에 그대로 남아 있어요."
    public static let laterTitle = "나중에 확인하기"

    /// 지웠던 내용이 다시 들어갈 수 있을 때 묻는 문구.
    public static func caution(_ caution: VerseDraftImportCheck.Caution) -> String {
        switch caution {
        case .verseClearedAfterDraft: "이 필기를 쓴 뒤 이 절이 지워졌어요. 넣으면 지웠던 절에 필기가 다시 들어가요."
        case .eraseAfterDraft: "이 필기를 쓴 뒤 ‘모든 필사 삭제’가 있었어요. 넣으면 지웠던 내용이 다시 들어갈 수 있어요."
        case .eraseHistoryUnknown: "삭제 기록을 확인하지 못했어요. 넣으면 지웠던 내용이 다시 들어갈 수 있어요."
        }
    }

    public static func cautionConfirmTitle(_ action: VerseDraftImportCheck.Action) -> String {
        action == .replace ? "그래도 바꾸기" : "그래도 넣기"
    }

    /// 지금 넣을 수 없는 까닭 — 목록 위에 한 번 적고 버튼을 막는다. 내용은 확인하고 비교할 수 있다.
    public static func importBlocked(_ block: SyncedWriteBlock) -> String {
        let reason = switch block {
        case .signedOut: "iCloud에 로그인하지 않았어요. 로그인한 뒤 앱을 다시 열면 넣을 수 있어요."
        case .accountUnconfirmed: "iCloud 계정을 확인하는 중이에요. 확인이 끝나면 넣을 수 있어요."
        case .ownershipUnverified: "이 iPad의 필사가 지금 iCloud 계정의 것인지 아직 확인하지 못했어요."
        case .knowledgeUnreadable: "삭제 기록을 읽지 못했어요. 앱을 다시 열어 보세요."
        case .verseFromOtherSession: "다른 계정을 쓰던 때의 필기라 지금 계정에 넣지 않아요."
        case .connectionHeld: "iCloud 연결을 마치려면 앱을 다시 열어 주세요."
        }
        return "지금은 현재 필사에 넣을 수 없어요. \(reason) 내용은 확인하고 비교할 수 있어요."
    }

    // MARK: - 넣은 뒤 — 저장을 마친 뒤에만 완료를 말한다

    public static func imported(_ place: String, previousKept: Bool) -> String {
        previousKept
            ? "\(place)의 필기를 이 필기로 바꿨어요. 이전 필기는 「이전 필사 내용 보기」에 남아 있어요."
            : "\(place)에 이 필기를 넣었어요."
    }

    public static func alreadyApplied(_ place: String) -> String {
        "\(place)의 현재 필사가 이미 이 필기와 같아요."
    }

    public static let currentChanged = "비교하는 사이 현재 필기가 바뀌었어요. 다시 비교한 내용을 확인해 주세요."
    public static let draftChanged = "남겨 둔 필기가 그 사이 바뀌었어요. 목록을 다시 읽었으니 다시 확인해 주세요."
    public static let importUnavailable = "위치 정보를 읽지 못해 현재 필사에 넣지 못했어요. 필기는 그대로 남아 있어요."
    public static let importFailed = "넣지 못했어요. 현재 필사와 남겨 둔 필기는 그대로예요. 다시 시도해 주세요."

    // MARK: - 형식

    /// "창세기 1:3". 책 이름을 읽지 못하면(모르는 원본 이름) 그 값을 그대로 보인다 — 어디인지 숨기지 않는다.
    public static func place(_ key: VerseDraftKey) -> String {
        let title = BibleTitle(rawValue: key.title)?.koreanTitle() ?? key.title
        return "\(title) \(key.chapter):\(key.verse)"
    }

    public static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 HH:mm"
        return formatter.string(from: date)
    }

    public static func bytesText(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
