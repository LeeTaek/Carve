//
//  PatchnoteView.swift
//  SettingsFeature
//
//  Created by Codex on 9/11/26.
//

import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: PatchnoteFeature.self)
public struct PatchnoteView: View {
    @Bindable public var store: StoreOf<PatchnoteFeature>

    public init(store: StoreOf<PatchnoteFeature>) {
        self.store = store
    }

    public var body: some View {
        CarveModalCard(title: "새기다 2.0", subtitle: "바뀐 점") {
            VStack(alignment: .leading, spacing: 24) {
                noteSection(
                    title: "필사 화면을 정리했어요",
                    body: "도구 팔레트가 아래로 내려가고, 쓰지 않을 땐 접혀요."
                )
                CarveDivider()
                noteSection(
                    title: "절을 길게 눌러보세요",
                    body: "이전 필사·이미지 저장·위젯·지우기를 한 자리에서."
                )
                CarveDivider()
                noteSection(
                    title: "필사를 이미지로 남겨요",
                    body: "본문과 필기를 한 장으로 합쳐 사진에 저장해요."
                )
                CarveDivider()
                noteSection(
                    title: "홈 화면 위젯",
                    body: "쓴 절을 지정하면 그 순간 모습이 위젯에 남아요."
                )

            }
        } actions: {
            Button {
                send(.helpTapped)
            } label: {
                Text("도움말 보기")
                    .foregroundStyle(CarveColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            Rectangle()
                .fill(CarveColor.divider)
                .frame(width: 1)
            Button {
                send(.closeTapped)
            } label: {
                Text("닫기")
                    .foregroundStyle(CarveColor.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
        }
    }

    private func noteSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CarveColor.ink)
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(CarveColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
