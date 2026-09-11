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
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: CarveSpacing.xxSmall) {
                    leadingControls
                    Spacer(minLength: 0)
                    trailingControls
                }

                titleButton
            }

            if store.showPalatte {
                PencilPalatteView(store: store.scope(state: \.palatteSetting,
                                                     action: \.palatteAction))
            }
        }
        .padding(.horizontal, CarveSpacing.large)
        .padding(.top, safeArea().top + CarveSpacing.small)
        .padding(.bottom, CarveSpacing.small)
        .background(CarveColor.canvas.ignoresSafeArea())
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
        .offset(y: -store.headerOffset < store.headerOffset
                ? store.headerOffset
                : (store.headerOffset < 0 ? store.headerOffset : 0))
        .ignoresSafeArea(.all, edges: .top)
    }

    private var leadingControls: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            CarveIconButton(.library, accessibilityLabel: "서재 열기") {
                send(.titleDidTapped)
            }
            if store.isLeftHanded {
                sentenceSettingsButton
            }
        }
    }

    private var trailingControls: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            CarveIconButton(.previous, accessibilityLabel: "이전 장") {
                send(.moveToBefore)
            }
            CarveIconButton(.next, accessibilityLabel: "다음 장") {
                send(.moveToNext)
            }
            // 하단 접힘 팔레트 작업 전까지 기존 팔레트 접근 경로를 유지한다.
            CarveIconButton(.pen, accessibilityLabel: "도구 팔레트", isSelected: store.showPalatte) {
                send(.pencilConfigDidTapped)
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
            isSelected: store.sentenceSettings != nil
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
                    .font(CarveTypography.scripture(ResourcesFontFamily.NanumMyeongjo.regular.font(size: 26)))
                Text("개역한글 · \(store.currentTitle.title.isOldtestment ? "구약" : "신약") / \(store.currentTitle.title.koreanTitle())")
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
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
