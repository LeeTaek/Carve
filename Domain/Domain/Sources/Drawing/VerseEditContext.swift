//
//  VerseEditContext.swift
//  Domain
//
//  Created by Claude on 9/18/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CryptoKit
import Foundation

/// 절 편집을 시작할 때 사용자가 보던 필기 — 편집의 **기준** (정책 §12-6 구현 순서 ①).
public enum VerseEditBase: Codable, Equatable, Sendable {
    /// 보이던 필기가 없었다.
    case empty
    /// legacy 행을 보고 편집했다. 첫 확정 때 이 원본을 `legacyImport` 로 수용해 부모로 삼는다(C3 ④a).
    case legacy(rowID: BibleDrawingRowID, contentFingerprint: String)
    /// 이 버전을 보고 편집했다. 끝이 둘 이상이던 절이면 **화면에 보이던 쪽**이다 — 다른 끝은 분기로 남는다.
    case version(versionID: String)
}

/// 편집 문맥이 기대는 계정 근거.
public enum VerseEditAccountBasis: Codable, Equatable, Sendable {
    /// 확인된 계정에서 시작했다. 표가 무효가 되면(계정 변경 알림 · 재확인) 문맥이 끝난다.
    case confirmed(AccountServerWorkToken)
    /// 계정을 확인하기 전에 시작했다. `hint` 는 그때의 마지막 확인 범위(참고 정보)다.
    case unverified(hint: AccountScope?)
    /// 로그인하지 않은 채 시작했다.
    case localOnly
}

/// 절 하나의 편집 문맥 — **계정 근거 · 기준 · K 를 편집을 시작할 때 함께 고정한다** (정책 §12-6 구현 순서 ①).
///
/// 장 전체의 전역 K 를 쓰면, 장을 연 뒤 삭제를 받은 화면에서 시작한 새 편집에 낡은 K 가 붙어 잘못 숨겨지거나, 원격 삭제를 받은 뒤
/// 낡은 화면 내용에 현재 K 를 붙여 지운 데이터를 되살린다. 그래서 절마다, 편집을 시작하는 순간의 값으로 묶는다.
public struct VerseEditContext: Codable, Equatable, Sendable {
    public let contextID: String
    public let verse: Int
    public let base: VerseEditBase
    /// 편집을 시작할 때 알던 삭제 기준점 집합. 이 문맥의 확정은 모두 이 K 를 잇는다(§12-6 C11 K 계승).
    public let knownEpochs: Set<String>
    public let account: VerseEditAccountBasis
    /// 이 문맥에서 마지막으로 확정한 버전. 같은 기기의 연속 확정은 이 버전을 부모로 잇는다.
    public private(set) var lastLocalCommitID: String?

    public init(
        contextID: String = UUID().uuidString,
        verse: Int,
        base: VerseEditBase,
        knownEpochs: Set<String>,
        account: VerseEditAccountBasis
    ) {
        self.contextID = contextID
        self.verse = verse
        self.base = base
        self.knownEpochs = knownEpochs
        self.account = account
    }

    /// 이 문맥에서 버전을 확정했다.
    public mutating func recordLocalCommit(_ versionID: String) {
        lastLocalCommitID = versionID
    }

    /// 다음 확정의 부모.
    ///
    /// **부모는 사용자가 편집한 화면의 기준이다.** 저장 시점의 "현재 끝" 을 부모로 삼으면 보지 않은 원격 편집을 반영한 척 충돌을 숨기고,
    /// 모든 끝을 부모로 삼는 것은 자동 해결이다. 보지 않은 원격 끝은 부모에 넣지 않고 분기로 남긴다.
    /// - Parameter legacyParentID: 기준이 legacy 행이면, 그 원본을 수용한 `legacyImport` 버전의 논리 ID(`LegacyVersionID`).
    /// - Returns: 부모 ID 들. 기준이 빈 절이고 아직 확정한 적이 없으면 빈 배열이다.
    public func parentIDs(legacyParentID: String?) -> [String] {
        if let lastLocalCommitID { return [lastLocalCommitID] }
        switch base {
        case .empty: return []
        case .version(let versionID): return [versionID]
        case .legacy: return legacyParentID.map { [$0] } ?? []
        }
    }
}

/// 편집 문맥이 아직 유효한가.
public enum VerseEditContextValidity: Equatable, Sendable {
    case valid
    /// 계정 확인을 기다린다 — 확인 전에 시작한 문맥이고 아직 확인되지 않았다. 확정(서버 작업)은 하지 않고 로컬 보존만 한다.
    case awaitingAccountConfirmation
    /// 문맥을 시작한 뒤 계정이 바뀌었거나, 시작할 때의 계정 근거를 지금 계정으로 이을 수 없다.
    case accountChanged
    /// 문맥을 시작한 뒤 모르던 삭제 기준점을 알게 됐다 — 편집 중이던 내용은 그 삭제를 모른 채 쓴 것이다.
    case eraseLearned
}

/// 편집 문맥의 유효성 판정 (정책 §12-6 구현 순서 ①). 순수 함수라 표로 시험한다.
///
/// 유효하지 않으면 호출부는 **문맥을 끝내고, 편집 중이던 내용을 격리한 뒤, 유효한 내용으로 다시 열고, 새 문맥을 시작한다.**
public enum VerseEditContextRule {
    /// - Parameters:
    ///   - context: 판정할 문맥.
    ///   - accountState: 지금 계정 상태.
    ///   - isTokenCurrent: 문맥이 든 표가 지금도 유효한가(`AccountScopeProvider.isCurrent`). 확인된 계정에서 시작한 문맥만 본다.
    ///   - deviceKnowledge: 지금 `K(기기)` — 문맥의 계정 범위의 것.
    public static func validity(
        of context: VerseEditContext,
        accountState: AccountScopeState,
        isTokenCurrent: Bool,
        deviceKnowledge: EraseEpochKnowledge
    ) -> VerseEditContextValidity {
        switch (context.account, accountState) {
        case (.confirmed, _):
            guard isTokenCurrent else { return .accountChanged }
        case (.unverified, .unconfirmed):
            // 아직 확인 전이다. K 는 확인 전에는 갱신되지 않으므로 기준점 판정만 이어서 본다.
            break
        case (.unverified(let hint), .confirmed(let scope)):
            // 확인 전에 시작한 편집을, 확인된 계정이 그때의 마지막 확인 계정과 같을 때만 잇는다. 다르면 그 편집이 본 내용이
            // 지금 계정의 것이라는 근거가 없다.
            guard let hint, hint == scope else { return .accountChanged }
        case (.unverified, .noAccount), (.localOnly, .confirmed), (.localOnly, .unconfirmed):
            // 로그인 안 함 ↔ 계정 사이는 자동으로 잇지 않는다 — 가져오기는 사용자가 명시적으로 하는 별도 작업이다.
            return .accountChanged
        case (.localOnly, .noAccount):
            break
        }
        guard EraseEpochRule.isValid(recordKnown: context.knownEpochs, device: deviceKnowledge) else {
            return .eraseLearned
        }
        if case .unverified = context.account, case .unconfirmed = accountState {
            return .awaitingAccountConfirmation
        }
        return .valid
    }
}

/// legacy 원본을 수용한 버전의 논리 ID (정책 §12-6 C3 ⑤).
///
/// **종류와 내용 지문을 늘 넣는다** — 같은 행이 A → B 로 바뀌면 다른 버전 ID 여야 불변 버전 규칙과 맞는다.
/// 삭제 관측(`legacyDelete`)은 그 행에서 마지막으로 보존한 내용 지문을 넣어 어떤 원본에 대한 삭제인지 고정한다.
public enum LegacyVersionID {
    /// 원본 행을 어떻게 가리키는가.
    public enum Source: Equatable, Sendable {
        /// 기기 간에 같은 물리 행을 가리키는 전역 식별자(`rowUUID`)가 있다 — 기기 간에 결정적이다.
        case global(rowUUID: String)
        /// 전역 식별자가 없다(1.3.0 행). 수용한 설치 · 기기 안의 보존 식별로 만든다 — 두 기기가 같은 원본을 올리면 레코드가 둘 생길 수
        /// 있다. **잘못 합치기보다 중복 보존을 택한다.**
        case deviceScoped(installID: String, preservationIdentity: String)
    }

    public static func make(kind: VerseDrawingVersionKind, source: Source, contentFingerprint: String) -> String {
        let components: [String] = switch source {
        case .global(let rowUUID): ["global", rowUUID]
        case .deviceScoped(let installID, let preservationIdentity): ["device", installID, preservationIdentity]
        }
        // 구성요소마다 길이를 앞에 붙여 경계를 고정한다 — 이어 붙인 문자열이 우연히 같아지는 것을 막는다.
        let canonical = (["carve.legacyVersion/1", kind.rawValue] + components + [contentFingerprint])
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return "legacy-" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
