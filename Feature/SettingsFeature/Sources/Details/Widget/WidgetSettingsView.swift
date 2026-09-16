//
//  WidgetSettingsView.swift
//  SettingsFeature
//
//  Created by Claude on 9/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import ComposableArchitecture
import UIComponents

/// 설정 → 위젯(시안 N7). 지금 표시 중인 말씀과 바꾸기 · 해제, 그리고 홈 화면에 위젯을 추가하는 방법을 함께 둔다.
@ViewAction(for: WidgetSettingsFeature.self)
public struct WidgetSettingsView: View {
    @Bindable public var store: StoreOf<WidgetSettingsFeature>

    public init(store: StoreOf<WidgetSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                    Text("위젯에 표시할 말씀")
                        .font(CarveTypography.sectionTitle)
                        .foregroundStyle(CarveColor.secondary)
                    Text("즐겨찾기에서 한 말씀을 골라 홈 화면에 띄워요.")
                        .font(CarveTypography.body)
                        .foregroundStyle(CarveColor.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                if store.hasLoaded {
                    if let current = store.current {
                        currentCard(current)
                    } else {
                        emptyCard
                    }
                }

                CarveDivider()

                homeScreenGuide
            }
            .padding(CarveSpacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CarveColor.surface)
        .sheet(isPresented: $store.isPickerPresented.sending(\.view.setPickerPresented)) {
            picker
        }
        .task {
            send(.task)
        }
    }

    /// 지금 표시 중인 말씀(시안 N7).
    private func currentCard(_ favorite: FavoriteVerseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            Text(Self.referenceText(favorite.key))
                .font(.title3)
                .foregroundStyle(CarveColor.ink)
            Text("\(favorite.key.translation.displayName) · 위젯에 표시 중")
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)
            Text(favorite.sentence)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, CarveSpacing.xxSmall)

            HStack(spacing: CarveSpacing.medium) {
                Button("표시할 말씀 바꾸기") {
                    send(.changeTapped)
                }
                .buttonStyle(.carve(.secondary))

                Button("위젯 표시 해제") {
                    send(.clearTapped)
                }
                .buttonStyle(.plain)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.secondary)
                .frame(minHeight: CarveSize.minimumHitTarget)
            }
            .disabled(store.isChanging)
            .padding(.top, CarveSpacing.xSmall)
        }
        .padding(CarveSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .carveSurface(.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 아직 고르지 않았을 때.
    private var emptyCard: some View {
        CarveEmptyState(
            "아직 고른 말씀이 없어요",
            message: "즐겨찾기에서 한 말씀을 골라 홈 화면에 띄워요.",
            actionTitle: "표시할 말씀 고르기"
        ) {
            send(.changeTapped)
        }
        .frame(maxWidth: .infinity)
    }

    /// 앱에서 고르는 것과 홈 화면에 위젯을 두는 것은 별개다(시안 N7).
    private var homeScreenGuide: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            Text("홈 화면에 위젯을 추가해 주세요")
                .font(.headline)
                .foregroundStyle(CarveColor.ink)
            Text("홈 화면을 길게 누르고 위젯 추가에서 새기다를 찾아 주세요.")
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
            Text("앱에서 말씀을 골라도 홈 화면 위젯이 자동으로 생기지는 않아요.")
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)
            Text("선택한 말씀은 홈 화면의 새기다 위젯에 함께 적용돼요.")
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(CarveSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 즐겨찾기에서 한 말씀을 고르는 시트(시안 N8). 취소하면 기존 대상을 그대로 둔다.
    private var picker: some View {
        NavigationStack {
            Group {
                if store.favorites.isEmpty {
                    CarveEmptyState(
                        "아직 즐겨찾기한 말씀이 없어요",
                        message: "필사 화면에서 절을 길게 눌러 즐겨찾기에 추가해 보세요.",
                        actionTitle: "닫기"
                    ) {
                        send(.setPickerPresented(false))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
                            Text("선택 후 적용을 누르면 위젯의 말씀이 바뀌어요.")
                                .font(CarveTypography.label)
                                .foregroundStyle(CarveColor.secondary)
                            ForEach(store.favorites) { favorite in
                                Button {
                                    send(.pickerSelected(favorite.key))
                                } label: {
                                    pickerRow(favorite)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(CarveSpacing.large)
                    }
                }
            }
            .background(CarveColor.surface)
            .navigationTitle("위젯에 표시할 말씀")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        send(.setPickerPresented(false))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        send(.pickerApplyTapped)
                    }
                    .disabled(store.pickerSelection == nil)
                }
            }
        }
    }

    private func pickerRow(_ favorite: FavoriteVerseSnapshot) -> some View {
        let isSelected = store.pickerSelection == favorite.key
        return HStack(alignment: .top, spacing: CarveSpacing.medium) {
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? CarveColor.accent : CarveColor.divider, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                if isSelected {
                    Circle()
                        .fill(CarveColor.accent)
                        .frame(width: 12, height: 12)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                Text(Self.referenceText(favorite.key))
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                Text(favorite.key.translation.displayName)
                    .font(CarveTypography.caption)
                    .foregroundStyle(CarveColor.secondary)
                Text(favorite.sentence)
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                    .lineLimit(2)
                    .padding(.top, CarveSpacing.xxSmall)
            }
            Spacer(minLength: 0)
        }
        .padding(CarveSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .carveSurface(.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// 「시편 23장 1절」. 장 단위는 필사 화면 헤더 · 즐겨찾기 목록과 같은 「장」 이다.
    static func referenceText(_ key: FavoriteVerseKey) -> String {
        "\(key.chapter.title.koreanTitle()) \(key.chapter.chapter)장 \(key.verse)절"
    }
}
