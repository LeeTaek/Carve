//
//  FirstRunGuideView.swift
//  CarveFeature
//
//  Created by Codex on 9/11/26.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: FirstRunGuideFeature.self)
public struct FirstRunGuideView: View {
    @Bindable public var store: StoreOf<FirstRunGuideFeature>

    public init(store: StoreOf<FirstRunGuideFeature>) {
        self.store = store
    }

    public var body: some View {
        CarveModalCard(title: "필사를 시작해 볼까요?") {
            VStack(alignment: .leading, spacing: 24) {
                guideSection(
                    title: "펜으로 쓰고, 손가락으로 스크롤해요",
                    body: "펜으로 말씀을 따라 써 보세요. 화면을 움직일 때는 손가락으로 밀어 주세요. 한 손가락으로도 스크롤할 수 있어요."
                )
                guideSection(
                    title: "필기 도구를 골라보세요",
                    body: "펜 버튼을 누르면 펜과 지우개를 바꾸고, 필기 색상을 고를 수 있어요."
                )
                guideSection(
                    title: "다른 성경으로 이동해요",
                    body: "왼쪽 위 탐색 버튼을 누르면 원하는 성경과 장을 고를 수 있어요."
                )
                guideSection(
                    title: "절을 길게 눌러보세요",
                    body: "이전 필사를 보거나 이미지로 저장하고, 위젯에 표시할 수 있어요. 지우기를 누르면 해당 절의 캔버스만 비워지고, 필사한 내용은 이전 필사에 남아요."
                )
            }
        } actions: {
            Button {
                send(.startTapped)
            } label: {
                Text("시작하기")
                    .foregroundStyle(CarveColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
        }
    }

    private func guideSection(title: String, body: String) -> some View {
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
