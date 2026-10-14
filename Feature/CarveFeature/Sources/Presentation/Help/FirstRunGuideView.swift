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
    /// 화면 언어 — 안내 페이지 문구를 이 값으로 만든다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    public init(store: StoreOf<FirstRunGuideFeature>) {
        self.store = store
    }

    public var body: some View {
        let guides = Self.guides(locale: locale)
        VStack {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: CarveSpacing.medium) {
                Text(verbatim: "\(store.currentPage + 1) / \(guides.count)")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.accent)

                TabView(selection: $store.currentPage) {
                    ForEach(Array(guides.enumerated()), id: \.offset) { index, guide in
                        guideSection(title: guide.title, body: guide.body)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 104)

                HStack(spacing: CarveSpacing.medium) {
                    Button {
                        send(.skipTapped)
                    } label: {
                        Text("건너뛰기", bundle: .module)
                    }
                    .buttonStyle(.plain)
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)

                    Spacer(minLength: 0)

                    HStack(spacing: CarveSpacing.xSmall) {
                        ForEach(guides.indices, id: \.self) { index in
                            Circle()
                                .fill(index == store.currentPage ? CarveColor.accent : CarveColor.divider)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .accessibilityHidden(true)

                    Spacer(minLength: 0)

                    Button {
                        send(.nextTapped)
                    } label: {
                        store.currentPage == guides.count - 1 ? Text("시작하기", bundle: .module) : Text("다음", bundle: .module)
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
        // 페이지 TabView 는 페이지를 가운데에 둔다. 위에 붙여 본문 길이와 상관없이 제목 위치를 고정한다.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 역할: 안내 페이지(제목 · 본문). 문구는 카탈로그에 있다 — 넘긴 로케일의 언어로 꺼낸다.
    /// 입력 · 출력: 로케일(뷰는 환경 locale 을 넘긴다) → 페이지 목록(`FirstRunGuideFeature.pageCount` 개).
    /// 부작용: 없음.
    private static func guides(locale: Locale) -> [(title: String, body: String)] {
        [
            (
                CarveFeatureCatalog.string("펜으로 쓰고, 손가락으로 스크롤해요", locale: locale),
                CarveFeatureCatalog.string(
                    "펜으로 말씀을 따라 써 보세요. 화면을 움직일 때는 손가락으로 밀어 주세요. 한 손가락으로도 스크롤할 수 있어요.",
                    locale: locale
                )
            ),
            (
                CarveFeatureCatalog.string("필기 도구를 골라보세요", locale: locale),
                CarveFeatureCatalog.string("펜 버튼을 누르면 펜과 지우개를 바꾸고, 필기 색상을 고를 수 있어요.", locale: locale)
            ),
            (
                CarveFeatureCatalog.string("다른 성경으로 이동해요", locale: locale),
                CarveFeatureCatalog.string("왼쪽 위 탐색 버튼을 누르면 원하는 성경과 장을 고를 수 있어요.", locale: locale)
            ),
            (
                CarveFeatureCatalog.string("절을 길게 눌러보세요", locale: locale),
                CarveFeatureCatalog.string(
                    "이전 필사를 보거나 이미지로 저장하고, 위젯에 표시할 수 있어요. 지우기를 누르면 해당 절의 캔버스만 비워지고, 필사한 내용은 이전 필사에 남아요.",
                    locale: locale
                )
            )
        ]
    }
}
