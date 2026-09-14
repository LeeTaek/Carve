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
    /// 버튼 줄 폭. 헤더 광고를 둘 자리가 있는지 판단한다.
    @State private var rowWidth: CGFloat = 0

    public init(store: StoreOf<HeaderFeature>) {
        self.store = store
    }

    public var body: some View {
        HeaderRowLayout {
            leadingControls
                .layoutValue(key: HeaderRowLayout.RoleKey.self, value: .leading)
            if showsAd {
                headerAd
                    .layoutValue(key: HeaderRowLayout.RoleKey.self, value: .ad)
            }
            titleButton
                .layoutValue(key: HeaderRowLayout.RoleKey.self, value: .title)
            trailingControls
                .layoutValue(key: HeaderRowLayout.RoleKey.self, value: .trailing)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            rowWidth = width
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
        .onAppear {
            send(.onAppear)
        }
    }

    /// 0은 펼침, 1은 축소. 본문 여백에 쓰는 측정 높이와 분리한다.
    private var collapseProgress: CGFloat {
        let distance = max(0, store.headerHeight - HeaderFeature.compactHeight)
        guard distance > 0 else { return 0 }
        return min(1, max(0, -store.headerOffset / distance))
    }

    /// 그리는 헤더 높이. 상태바가 높은 기기에서도 축소 버튼 줄을 담는다.
    private var displayedHeaderHeight: CGFloat {
        HeaderFeature.displayedHeight(collapseProgress: collapseProgress, safeAreaTop: safeArea().top)
    }

    private var controlsTopPadding: CGFloat {
        HeaderFeature.controlsTopPadding(collapseProgress: collapseProgress, safeAreaTop: safeArea().top)
    }

    /// 축소 중에도 44pt 탭 영역은 유지하고, 버튼의 아이콘과 표면만 작게 보인다.
    private var buttonVisualScale: CGFloat {
        1 - 0.14 * collapseProgress
    }

    /// 광고를 받는 중이거나 받았고, 가운데 제목과 서재 쪽 버튼 사이에 광고 필수 요소가 들어갈 폭이 있을 때만 헤더 광고 자리를 둔다.
    private var showsAd: Bool {
        store.adSlot.occupiesSpace
            && HeaderAdLayout.adWidth(
                rowWidth: rowWidth,
                leadingWidth: HeaderAdLayout.buttonGroupWidth(1)
            ) != nil
    }

    /// 헤더 줄 광고(시안 K2). 폭은 `HeaderRowLayout` 이 고정 폭으로 주고, 높이는 헤더 축소를 따라 56 ↔ 44pt 로 바뀐다.
    /// VoiceOver 는 버튼 · 제목 뒤에 읽는다.
    private var headerAd: some View {
        AdSlotView(store: store.scope(state: \.adSlot, action: \.adSlot))
            .frame(height: HeaderAdLayout.height(collapseProgress: collapseProgress))
            .accessibilitySortPriority(-1)
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
            // 실기기 UI 테스트가 찾는 식별자. 접근성 이름(「다음 장」)이 문구 변경으로 바뀌어도 유지한다.
            .accessibilityIdentifier("nextChapter")
            // 왼손 모드에서도 오른쪽에 고정한다. 서재 쪽에 버튼이 늘면 헤더 광고가 들어갈 자리가 사라진다.
            sentenceSettingsButton
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
                    // 세로 화면에서 광고와 함께 두면 폭이 좁아진다. 줄바꿈 대신 줄여 그린다.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("개역한글 · \(store.currentTitle.title.isOldtestment ? "구약" : "신약") / \(store.currentTitle.title.koreanTitle())")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
