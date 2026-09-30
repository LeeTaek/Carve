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
        VStack {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: CarveSpacing.medium) {
                Text("\(store.currentPage + 1) / \(Self.guides.count)")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.accent)

                TabView(selection: $store.currentPage) {
                    ForEach(Array(Self.guides.enumerated()), id: \.offset) { index, guide in
                        guideSection(title: guide.title, body: guide.body)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 104)

                HStack(spacing: CarveSpacing.medium) {
                    Button("건너뛰기") {
                        send(.skipTapped)
                    }
                    .buttonStyle(.plain)
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)

                    Spacer(minLength: 0)

                    HStack(spacing: CarveSpacing.xSmall) {
                        ForEach(Self.guides.indices, id: \.self) { index in
                            Circle()
                                .fill(index == store.currentPage ? CarveColor.accent : CarveColor.divider)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)

                    Spacer(minLength: 0)

                    Button(store.currentPage == Self.guides.count - 1 ? "시작하기" : "다음") {
                        send(.nextTapped)
                    }
                    .buttonStyle(.carve(.primary))
                }
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: 500)
            .carveSurface(
                .panel,
                in: RoundedRectangle(cornerRadius: CarveRadius.panel, style: .continuous)
            )
            .padding(.horizontal, CarveSpacing.large)
            .padding(.bottom, CarveSpacing.xSmall)
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

    private static let guides: [(title: String, body: String)] = [
        (
            "펜으로 쓰고, 손가락으로 스크롤해요",
            "펜으로 말씀을 따라 써 보세요. 화면을 움직일 때는 손가락으로 밀어 주세요. 한 손가락으로도 스크롤할 수 있어요."
        ),
        (
            "필기 도구를 골라보세요",
            "펜 버튼을 누르면 펜과 지우개를 바꾸고, 필기 색상을 고를 수 있어요."
        ),
        (
            "다른 성경으로 이동해요",
            "왼쪽 위 탐색 버튼을 누르면 원하는 성경과 장을 고를 수 있어요."
        ),
        (
            "절을 길게 눌러보세요",
            "이전 필사를 보거나 이미지로 저장하고, 위젯에 표시할 수 있어요. 지우기를 누르면 해당 절의 캔버스만 비워지고, 필사한 내용은 이전 필사에 남아요."
        )
    ]
}
