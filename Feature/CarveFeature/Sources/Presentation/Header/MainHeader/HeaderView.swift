//
//  HeaderView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Resources
import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: HeaderFeature.self)
public struct HeaderView: View {
    @Bindable public var store: StoreOf<HeaderFeature>

    public init(store: StoreOf<HeaderFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            HStack(spacing: CarveSpacing.xxSmall) {
                leadingControls
                Spacer(minLength: 0)
                trailingControls
            }

            titleButton
        }
        .padding(.horizontal, CarveSpacing.large)
        .padding(.top, controlsTopPadding)
        .frame(height: displayedHeaderHeight, alignment: .top)
        .background(CarveColor.canvas.ignoresSafeArea())
        // ⚠️ 측정 높이는 펼친 높이로 고정한다. 그리는 높이(`displayedHeaderHeight`)는 측정값(`headerHeight`)으로
        //    진행률을 계산하므로, 그리는 높이를 재면 측정 → 진행률 → 높이가 되먹여 118 ↔ 78 을 오간다
        //    ("Geometry action is cycling between duplicate values"). 그 값이 본문 상단 여백이라 매번 재배치된다.
        //    빈 아래 띠는 히트 테스트되지 않아 필기 입력을 막지 않는다.
        .frame(height: HeaderFeature.expandedHeight, alignment: .top)
        .anchorPreference(key: HeaderBoundsKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(HeaderBoundsKey.self) { value in
            if value != nil {
                Color.clear
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { proxySize in
                                    send(.setHeaderHeight(proxySize))
                                }
                        }
                    )
            }
        }
        .animation(.easeInOut(duration: 0.16), value: store.headerOffset)
        .animation(.easeInOut(duration: 0.16), value: store.isManuallyCollapsed)
        .animation(.easeInOut(duration: 0.16), value: store.isNavigationPresented)
        .ignoresSafeArea(.all, edges: .top)
    }

    /// 0은 펼침, 1은 축소. 본문 여백에 쓰는 측정 높이와 분리한다.
    private var collapseProgress: CGFloat {
        let distance = max(0, store.headerHeight - HeaderFeature.compactHeight)
        guard distance > 0 else { return 0 }
        return min(1, max(0, -store.headerOffset / distance))
    }

    private var displayedHeaderHeight: CGFloat {
        HeaderFeature.expandedHeight - (HeaderFeature.expandedHeight - HeaderFeature.compactHeight) * collapseProgress
    }

    private var controlsTopPadding: CGFloat {
        safeArea().top + 28 - 18 * collapseProgress
    }

    /// 축소 중에도 44pt 탭 영역은 유지하고, 버튼의 아이콘과 표면만 작게 보인다.
    private var buttonVisualScale: CGFloat {
        1 - 0.14 * collapseProgress
    }

    private var leadingControls: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            CarveIconButton(
                navigationIcon,
                accessibilityLabel: navigationAccessibilityLabel,
                isSelected: store.isNavigationPresented,
                visualScale: buttonVisualScale
            ) {
                send(.libraryDidTapped)
            }
            if store.isLeftHanded {
                sentenceSettingsButton
            }
        }
    }

    private var navigationIcon: CarveIcon {
        .library
    }

    private var navigationAccessibilityLabel: String {
        store.isNavigationPresented ? "성경 탐색 닫기" : "성경 탐색 열기"
    }

    private var trailingControls: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            CarveIconButton(.previous, accessibilityLabel: "이전 장", visualScale: buttonVisualScale) {
                send(.moveToBefore)
            }
            CarveIconButton(.next, accessibilityLabel: "다음 장", visualScale: buttonVisualScale) {
                send(.moveToNext)
            }
            if !store.isLeftHanded {
                sentenceSettingsButton
            }
        }
    }

    private var sentenceSettingsButton: some View {
        CarveIconButton(
            .textFormat,
            accessibilityLabel: "본문 설정",
            isSelected: store.sentenceSettings != nil,
            visualScale: buttonVisualScale
        ) {
            send(.sentenceSettingsDidTapped)
        }
        .popover(
            item: $store.scope(state: \.sentenceSettings, action: \.sentenceSettings),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) { settingsStore in
            SentenceSettingsView(store: settingsStore)
                .frame(width: 350, height: 560)
        }
    }

    private var titleButton: some View {
        Button {
            send(.titleDidTapped)
        } label: {
            VStack(spacing: 2) {
                Text("\(store.currentTitle.title.koreanTitle()) \(store.currentTitle.chapter)장")
                    .font(CarveTypography.scripture(ResourcesFontFamily.NanumMyeongjo.regular.font(size: 26 - 10 * collapseProgress)))
                Text("개역한글 · \(store.currentTitle.title.isOldtestment ? "구약" : "신약") / \(store.currentTitle.title.koreanTitle())")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                    .opacity(1 - collapseProgress)
                    .frame(height: 14 * (1 - collapseProgress), alignment: .top)
            }
            .foregroundStyle(CarveColor.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, CarveSpacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(store.currentTitle.title.koreanTitle()) \(store.currentTitle.chapter)장, 성경과 장 목록 열기")
    }
}
