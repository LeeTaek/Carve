//
//  HelpView.swift
//  SettingsFeature
//
//  Created by Codex on 9/11/26.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: HelpFeature.self)
public struct HelpView: View {
    @Bindable public var store: StoreOf<HelpFeature>

    public init(store: StoreOf<HelpFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                CarvePanelHeader("도움말")
                    .padding(.horizontal, -CarveSpacing.large)

                helpSection(
                    title: "두 손가락으로 스크롤",
                    body: "Apple Pencil은 필사에 쓰고, 화면은 손가락으로 밀어 올려요. 한 손가락으로도 스크롤할 수 있어요."
                )
                helpSection(
                    title: "절을 길게 눌러 메뉴 열기",
                    body: "이전 필사 보기 · 이미지 저장 · 위젯에 표시 · 지우기가 나와요."
                )
                helpSection(
                    title: "이미지로 저장하기",
                    body: "본문과 필기를 한 장으로 합쳐 사진에 저장해요."
                )
                helpSection(
                    title: "위젯에 표시하기",
                    body: "지정한 순간의 모습이 위젯에 남아요. 홈 화면에 위젯을 먼저 추가해 주세요."
                )

                Button {
                    send(.restartFirstRunGuideTapped)
                } label: {
                    Text("처음부터 다시 보기")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.carve(.secondary))
            }
            .padding(CarveSpacing.large)
        }
        .background(CarveColor.canvas)
    }

    private func helpSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            Text(title)
                .font(CarveTypography.body.weight(.semibold))
                .foregroundStyle(CarveColor.ink)
            Text(body)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
