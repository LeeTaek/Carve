//
//  HeaderView.swift
//  FeatureCarve
//
//  Created by 이택성 on 5/27/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Domain
import Resources
import SwiftUI

import ComposableArchitecture
import UIComponents

@ViewAction(for: HeaderFeature.self)
public struct HeaderView: View {
    @Bindable public var store: StoreOf<HeaderFeature>
    /// 버튼 줄 폭. 헤더 광고를 둘 자리가 있는지 판단한다.
    @State private var rowWidth: CGFloat = 0
    /// 화면 언어 — 앱 안에서 언어를 고르면 앱 루트가 바꾼다. 미리 만드는 문구(제목 · 접근성 이름)는 이 값으로 만든다(즉시 전환 단계 2).
    @Environment(\.locale) private var locale

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
        store.isNavigationPresented
            ? CarveFeatureCatalog.string("성경 탐색 닫기", locale: locale)
            : CarveFeatureCatalog.string("성경 탐색 열기", locale: locale)
    }

    private var trailingControls: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            CarveIconButton(.previous, accessibilityLabel: CarveFeatureCatalog.string("이전 장", locale: locale), visualScale: buttonVisualScale) {
                send(.moveToBefore)
            }
            CarveIconButton(.next, accessibilityLabel: CarveFeatureCatalog.string("다음 장", locale: locale), visualScale: buttonVisualScale) {
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
            accessibilityLabel: CarveFeatureCatalog.string("본문 설정", locale: locale),
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
            // 높이는 기본 글자 크기에서 내용(영어 약 690pt — 「손가락 필사 허용」 설명이 두 줄)이 다 들어가는 값이다.
            // 560 이면 그 설명 둘째 줄 중간에서 잘려 보였다(2.1.0 출시 시험 EN-UI1). 더 큰 글자나 낮은 화면에서는 시스템이 줄이고 안에서 민다.
            SentenceSettingsView(store: settingsStore)
                .frame(width: 350, height: 712)
        }
    }

    /// 헤더 제목 — 누르면 번역본 고르기 팝오버가 열린다(영어 현지화 결정 19). 고르면 같은 권 · 장 · 지금 보던 절로 간다(결정 9 —
    /// `CarveNavigationFeature.switchTranslation`). 탐색 열은 서재 버튼으로 연다.
    /// 시스템 `Menu` 대신 본문 설정과 같은 앱 팝오버 표면에 그린다(`TranslationPickerView`).
    private var titleButton: some View {
        Button {
            send(.titleDidTapped)
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: Self.titleText(store.currentTitle, locale: locale))
                    .font(CarveTypography.scripture(ResourcesFontFamily.NanumMyeongjo.regular.font(size: 26 - 10 * collapseProgress)))
                    // 세로 화면에서 광고와 함께 두면 폭이 좁아진다. 줄바꿈 대신 줄여 그린다.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                // 번역본 약칭은 지금 장의 번역본이다(결정 11). 끝의 ⌄ 로 눌러서 번역본을 바꿀 수 있음을 알린다.
                HStack(spacing: CarveSpacing.xxSmall) {
                    Text(verbatim: Self.subtitleText(store.currentTitle, locale: locale))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
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
        .accessibilityLabel(Self.titleAccessibilityLabel(store.currentTitle, locale: locale))
        .accessibilityValue(Text(verbatim: store.currentTitle.translation.fullName(locale: locale)))
        .popover(isPresented: translationPickerPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            // 지금 번역본은 공유 장(`currentTitle`)이 정한다. 고르면 리듀서로 보내고, 헤더 리듀서가 팝오버를 닫는다.
            TranslationPickerView(selection: store.currentTitle.translation) { translation in
                send(.translationSelected(translation))
            }
        }
    }

    /// 번역본 고르기 팝오버의 표시 여부. 바깥을 눌러 닫히면 리듀서에 알린다.
    private var translationPickerPresented: Binding<Bool> {
        Binding(
            get: { store.isTranslationPickerPresented },
            set: { isPresented in
                if !isPresented { send(.translationPickerDismissed) }
            }
        )
    }
}

// MARK: - 제목 문구

extension HeaderView {
    /// 역할: 헤더 제목(「창세기 1장」 · 「Genesis 1」). 권 이름 · 장 표기는 번역본이 아니라 앱 언어를 따른다(영어 현지화 결정 3).
    /// 입력 · 출력: 지금 장 · 로케일(뷰는 환경 locale 을 넘긴다) → 참조 문자열(`BibleReference`, 약칭 없음 — 부제가 적는다).
    /// 부작용: 없음.
    static func titleText(_ chapter: BibleChapter, locale: Locale) -> String {
        BibleReference(chapter: chapter).text(locale: locale)
    }

    /// 역할: 헤더 부제(「개역개정 · 구약 / 창세기」 · 「KJV · Old Testament / Genesis」).
    /// 입력 · 출력: 지금 장 · 로케일(뷰는 환경 locale 을 넘긴다) → 번역본 약칭 · 구약/신약 · 권 이름.
    /// 부작용: 없음.
    static func subtitleText(_ chapter: BibleChapter, locale: Locale) -> String {
        let testament = chapter.title.isOldtestment
            ? CarveFeatureCatalog.string("구약", locale: locale)
            : CarveFeatureCatalog.string("신약", locale: locale)
        return "\(chapter.translation.displayName(locale: locale)) · \(testament) / \(chapter.title.localizedName(locale: locale))"
    }

    /// 역할: 제목 메뉴의 VoiceOver 이름(「창세기 1장, 번역본 바꾸기」). 지금 번역본은 값(`accessibilityValue`)으로 읽는다.
    /// 입력 · 출력: 지금 장 · 로케일(뷰는 환경 locale 을 넘긴다) → 제목과 메뉴가 하는 일.
    /// 부작용: 없음.
    static func titleAccessibilityLabel(_ chapter: BibleChapter, locale: Locale) -> String {
        CarveFeatureCatalog.string("\(titleText(chapter, locale: locale)), 번역본 바꾸기", locale: locale)
    }

    /// 역할: 번역본 고르기 항목의 VoiceOver 이름 — 약칭과 전체 이름. 둘이 같으면(한국어의 개역개정) 한 번만 적는다.
    /// 입력 · 출력: 번역본 · 로케일(뷰는 환경 locale 을 넘긴다) → 「KJV · King James Version」 · 「개역개정」.
    /// 부작용: 없음.
    static func translationMenuTitle(_ translation: Translation, locale: Locale) -> String {
        let abbreviation = translation.displayName(locale: locale)
        let fullName = translation.fullName(locale: locale)
        return abbreviation == fullName ? abbreviation : "\(abbreviation) · \(fullName)"
    }
}
