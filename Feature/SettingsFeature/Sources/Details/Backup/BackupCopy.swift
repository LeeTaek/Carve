//
//  BackupCopy.swift
//  SettingsFeature
//
//  설정 → 「필사 백업」 의 문구를 한곳에 둔다 — 같은 사실을 화면마다 다르게 말하지 않게(설계 docs/backup-import-design.md §3 · §5-2).
//  「원문」 이라고 적은 것은 공통 규칙(plan 노트 인터뷰 기록)의 문장 그대로다 — 고치지 않는다.
//

import Foundation

public enum BackupCopy {
    /// 화면 이름 — 설정 사이드바의 행 이름이자 화면 제목.
    public static let title = "필사 백업"

    /// 무엇을 담고 무엇을 담지 않는가(원문 — 설계 §3-1 2단계).
    public static let exportScope = "이 기기에 저장된 필사를 백업해요. 아직 동기화되지 않은 다른 기기의 필사는 포함되지 않을 수 있어요. "
        + "즐겨찾기 · 설정 · 위젯은 담지 않아요."

    /// 암호를 잃으면 열 수 없다(원문 — 설계 §3-1 2단계).
    public static let passwordWarning = "암호를 잊으면 Carve 도 이 파일을 열 수 없어요."

    /// 불러오면 어디에 무엇이 되는가(원문 — 설계 §4-1 6단계).
    public static let importGuidance = "불러온 필사는 이 기기에 저장되고, 지금 연결된 iCloud 계정으로 동기화돼요. "
        + "지금 필사는 그대로 두고, 다른 내용은 이전 필사 기록에 더해요."

    // MARK: - 화면의 두 줄

    public static let exportTitle = "백업 만들기"
    public static let exportDescription = "암호를 건 백업 파일 하나로 저장해요. 저장할 곳은 직접 골라요."
    public static let exportAction = "만들기"
    /// 사지 않은 사람에게 만들기 대신 보이는 안내(설계 §3-1 1단계 — 불러오기는 그대로 열린다).
    public static let purchaseRequired = "광고 제거를 구매하면 백업을 만들 수 있어요."
    public static let purchaseAction = "광고 제거 보기"

    public static let importTitle = "백업 불러오기"
    public static let importDescription = "백업 파일의 필사를 이 기기에 더해요. 불러오기는 구매하지 않아도 쓸 수 있어요."
    public static let importAction = "불러오기"

    // MARK: - 암호

    public static let passwordPlaceholder = "암호(8자 이상)"
    public static let passwordConfirmationPlaceholder = "암호 확인"
    public static let startAction = "백업 만들기"

    /// 암호로 시작할 수 없는 까닭.
    public static func passwordIssue(_ issue: BackupExportFeature.PasswordIssue) -> String {
        switch issue {
        case .tooShort: "암호는 \(BackupExportFeature.minimumPasswordLength)자 이상이어야 해요."
        case .mismatch: "두 암호가 같지 않아요."
        }
    }

    // MARK: - 마지막 필기 저장(flush)

    /// 필사 화면의 마지막 필기가 이 기기에 남기를 기다리는 동안.
    public static let flushing = "마지막 필기를 저장하는 중이에요"

    /// flush 가 `.durable` 이 아니어서 백업을 시작하지 않았다(원문 — 설계 §5-2).
    public static let flushBlocked = "필사 화면에 아직 저장하지 못한 필기가 있어요. 필사 화면에서 저장을 다시 시도한 뒤 백업해 주세요."

    public static let retryAction = "다시 시도"

    // MARK: - 파일 만들기

    /// 진행 한 줄 — 장 단위. 장을 다 읽은 뒤에는 암호를 걸어 쓰고 다시 열어 확인한다.
    public static func exporting(_ progress: BackupExportFeature.ExportProgress?) -> String {
        guard let progress, progress.total > 0 else { return "백업 파일을 만드는 중이에요" }
        if progress.done >= progress.total {
            return "암호를 걸어 파일을 쓰고, 다시 열어 확인하는 중이에요"
        }
        return "필사를 모으는 중이에요 · \(progress.done)/\(progress.total)장"
    }

    /// 파일을 만들지 못한 까닭과 할 일. [다시 시도] 를 함께 둔다.
    public static func exportFailed(_ failure: BackupExportFeature.ExportFailure) -> String {
        switch failure {
        case .generationChanged:
            "백업을 만드는 사이 ‘모든 필사 삭제’가 실행됐어요. 다시 시도하면 지금 남은 필사로 처음부터 만들어요."
        case .accountChanged:
            "백업을 만드는 사이 iCloud 계정 상태가 바뀌었어요. 다른 계정의 필기가 한 파일에 섞이지 않도록 멈췄어요. 다시 시도해 주세요."
        case .storeUnreadable:
            "저장된 필사를 읽지 못해 백업을 만들지 못했어요. 잠시 뒤 다시 시도해 주세요."
        case .draftsUnreadable:
            "이 iPad에 남겨 둔 필기 일부를 읽지 못해 멈췄어요. 설정의 ‘확인이 필요한 필기’에서 확인할 수 있어요."
        case .insufficientSpace:
            "iPad의 저장 공간이 부족해 백업 파일을 만들지 못했어요. 공간을 비운 뒤 다시 시도해 주세요."
        case .writeFailed:
            "백업 파일을 만들지 못했어요. 다시 시도해 주세요."
        case .verificationFailed:
            "만든 파일을 다시 열어 확인했더니 내용이 맞지 않아 내놓지 않았어요. 다시 시도해 주세요."
        case .unavailable:
            "지금은 백업을 만들 수 없어요. 앱을 다시 연 뒤 시도해 주세요."
        }
    }

    // MARK: - 저장 위치 · 결과

    public static let chooseLocation = "백업 파일을 만들었어요. 저장할 곳을 골라 주세요."
    public static let chooseLocationAction = "저장할 곳 고르기"

    /// 저장했다 — 담은 수. 파일 이름은 사용자가 바꿀 수 있어 따로 한 줄로 적는다(`savedFileName`).
    public static func saved(rows: Int, drafts: Int) -> String {
        "백업 파일을 저장했어요. 필사 기록 \(rows)개 · 남겨 둔 필기 \(drafts)개를 담았어요."
    }

    /// 저장한 파일 이름 한 줄.
    public static func savedFileName(_ fileName: String) -> String {
        "파일 이름: \(fileName)"
    }

    /// 앱의 저장 성공과 저장한 곳(iCloud Drive 등)의 업로드는 별개다(설계 §3-1 8단계).
    public static let savedProviderNote = "iCloud Drive 같은 곳에 저장했다면, 그곳으로 올리는 일은 그 앱이 이어서 마쳐요."
    public static let saveCancelled = "저장하지 않았어요. 만든 파일은 이 iPad에서 지웠어요."
    public static let saveFailed = "고른 곳에 저장하지 못했어요. 만든 파일은 이 iPad에서 지웠어요. 다시 만들어 주세요."
    public static let remakeAction = "다시 만들기"

    public static let closeAction = "닫기"
    public static let cancelAction = "취소"
}
