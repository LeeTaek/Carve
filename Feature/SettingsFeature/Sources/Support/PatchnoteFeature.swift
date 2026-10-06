//
//  PatchnoteFeature.swift
//  SettingsFeature
//
//  Created by Codex on 9/11/26.
//

import ComposableArchitecture

/// 릴리스 변경 사항을 보여주는 패치노트.
@Reducer
public struct PatchnoteFeature {
    public init() { }

    @ObservableState
    public struct State: Equatable, Hashable, Sendable {
        public static let initialState = Self()
    }

    public enum Action: ViewAction {
        case delegate(Delegate)
        case view(View)

        public enum Delegate {
            case close
            case showHelp
        }

        public enum View {
            case closeTapped
            case helpTapped
        }
    }

    public var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .view(.closeTapped):
                return .send(.delegate(.close))
            case .view(.helpTapped):
                return .send(.delegate(.showHelp))
            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - 내용

extension PatchnoteFeature {
    /// 한 번의 출시에서 바뀐 점.
    public struct Release: Hashable, Identifiable, Sendable {
        /// 보이는 버전 — 「새기다 2.1」 의 2.1.
        public let version: String
        /// 바뀐 점 — 보이는 차례대로.
        public let notes: [Note]

        public var id: String { version }
    }

    /// 바뀐 점 한 가지 — 제목과 한두 문장.
    public struct Note: Hashable, Sendable {
        public let title: String
        public let body: String
    }

    /// 출시별 바뀐 점. **최근 출시가 앞이다** — 업데이트 뒤 자동으로 띄우는 창은 첫 출시만 보이고, 설정의 패치노트는 모두 보인다.
    public static let releases: [Release] = [
        Release(version: "2.1", notes: [
            Note(
                title: "필사 백업 · 불러오기",
                body: "설정의 필사 백업에서 암호를 건 파일로 필사를 백업하고 다시 불러와요. 백업 만들기는 광고 제거 구매에 포함되고, 불러오기는 무료예요."
            ),
            Note(
                title: "필사 캔버스는 하나로",
                body: "절마다 쓰는 캔버스 설정이 없어졌어요. 그동안 쓴 필사는 그대로예요."
            ),
            Note(
                title: "본문 표시를 바로잡았어요",
                body: "일부 장에서 절이 겹치거나 줄이 따로 떨어져 보이던 문제와 합쳐진 절 · 시편 권 표시를 고쳤어요. 가로 화면에서 장 목록이 내려앉던 문제도 고쳤어요."
            )
        ]),
        Release(version: "2.0", notes: [
            Note(title: "필사 화면을 정리했어요", body: "도구 팔레트가 아래로 내려가고, 쓰지 않을 땐 접혀요."),
            Note(title: "절을 길게 눌러보세요", body: "이전 필사·이미지 저장·위젯·지우기를 한 자리에서."),
            Note(title: "필사를 이미지로 남겨요", body: "본문과 필기를 한 장으로 합쳐 사진에 저장해요."),
            Note(title: "홈 화면 위젯", body: "쓴 절을 지정하면 그 순간 모습이 위젯에 남아요.")
        ])
    ]

    /// 가장 최근 출시 — 업데이트 뒤 자동으로 띄우는 창의 내용.
    public static var latest: Release { releases[0] }
}
