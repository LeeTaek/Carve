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

/// 설정 → 위젯(시안 N7). 지금 담긴 말씀들과 고르기 · 모두 빼기, 그리고 홈 화면에 위젯을 추가하는 방법을 함께 둔다.
@ViewAction(for: WidgetSettingsFeature.self)
public struct WidgetSettingsView: View {
    @Bindable public var store: StoreOf<WidgetSettingsFeature>
    /// 화면 언어 — 앱 안에서 언어를 고르면 참조(권 이름 · 장절) · 번역본 약칭 · 빈 상태 문구도 바로 따라온다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    public init(store: StoreOf<WidgetSettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CarveSpacing.large) {
                header

                if store.hasLoaded {
                    if store.selected.isEmpty {
                        emptyCard
                    } else {
                        selectedCard
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

    private var header: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
            Text("위젯에 담은 말씀", bundle: .module)
                .font(CarveTypography.sectionTitle)
                .foregroundStyle(CarveColor.secondary)
            Text("즐겨찾기에서 고른 말씀을 홈 화면에 띄워요. 여러 개를 담으면 한 시간에 하나씩 돌아가며 보여요.", bundle: .module)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// 지금 담긴 말씀들(시안 N7).
    private var selectedCard: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
            Text("\(store.selected.count)개 담김 · 최대 \(WidgetVerseLimit.maximum)개", bundle: .module)
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)

            VStack(alignment: .leading, spacing: CarveSpacing.small) {
                ForEach(store.selected) { favorite in
                    selectedRow(favorite)
                }
            }

            HStack(spacing: CarveSpacing.medium) {
                Button {
                    send(.changeTapped)
                } label: {
                    Text("담은 말씀 고르기", bundle: .module)
                }
                .buttonStyle(.carve(.secondary))

                Button {
                    send(.clearTapped)
                } label: {
                    Text("위젯에서 모두 빼기", bundle: .module)
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

    private func selectedRow(_ favorite: FavoriteVerseSnapshot) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
            Text(Self.referenceText(favorite.key, showsTranslation: true, locale: locale))
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
            Text(favorite.sentence)
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 아직 고르지 않았을 때.
    private var emptyCard: some View {
        CarveEmptyState(
            SettingsCatalog.string("아직 담은 말씀이 없어요", locale: locale),
            message: SettingsCatalog.string("즐겨찾기에서 말씀을 골라 홈 화면에 띄워요.", locale: locale),
            actionTitle: SettingsCatalog.string("담을 말씀 고르기", locale: locale)
        ) {
            send(.changeTapped)
        }
        .frame(maxWidth: .infinity)
    }

    /// 앱에서 고르는 것과 홈 화면에 위젯을 두는 것은 별개다(시안 N7).
    private var homeScreenGuide: some View {
        VStack(alignment: .leading, spacing: CarveSpacing.small) {
            Text("홈 화면에 위젯을 추가해 주세요", bundle: .module)
                .font(.headline)
                .foregroundStyle(CarveColor.ink)
            Text("홈 화면을 길게 누르고 위젯 추가에서 새기다를 찾아 주세요.", bundle: .module)
                .font(CarveTypography.body)
                .foregroundStyle(CarveColor.ink)
            Text("앱에서 말씀을 골라도 홈 화면 위젯이 자동으로 생기지는 않아요.", bundle: .module)
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)
            Text("담은 말씀은 홈 화면의 새기다 위젯에 함께 적용되고, 한 시간마다 차례가 넘어가요.", bundle: .module)
                .font(CarveTypography.label)
                .foregroundStyle(CarveColor.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(CarveSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CarveColor.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// 즐겨찾기에서 말씀을 고르는 시트(시안 N8). 취소하면 담긴 말씀을 그대로 둔다.
    private var picker: some View {
        NavigationStack {
            Group {
                if store.favorites.isEmpty {
                    CarveEmptyState(
                        SettingsCatalog.string("아직 즐겨찾기한 말씀이 없어요", locale: locale),
                        message: SettingsCatalog.string("필사 화면에서 절을 길게 눌러 즐겨찾기에 추가해 보세요.", locale: locale),
                        actionTitle: SettingsCatalog.string("닫기", locale: locale)
                    ) {
                        send(.setPickerPresented(false))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: CarveSpacing.medium) {
                            Text("\(store.pickerSelection.count) / \(WidgetVerseLimit.maximum)개 선택 · 적용을 누르면 위젯이 바뀌어요.", bundle: .module)
                                .font(CarveTypography.label)
                                .foregroundStyle(CarveColor.secondary)
                            ForEach(store.favorites) { favorite in
                                Button {
                                    send(.pickerToggled(favorite.key))
                                } label: {
                                    pickerRow(favorite)
                                }
                                .buttonStyle(.plain)
                                // 꽉 찬 뒤에도 이미 고른 것은 끌 수 있어야 한다.
                                .disabled(!store.canSelectMore && !store.pickerSelection.contains(favorite.key))
                            }
                        }
                        .padding(CarveSpacing.large)
                    }
                }
            }
            .background(CarveColor.surface)
            .navigationTitle(Text("위젯에 담을 말씀", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        send(.setPickerPresented(false))
                    } label: {
                        Text("취소", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        send(.pickerApplyTapped)
                    } label: {
                        Text("적용", bundle: .module)
                    }
                }
            }
        }
    }

    private func pickerRow(_ favorite: FavoriteVerseSnapshot) -> some View {
        let isSelected = store.pickerSelection.contains(favorite.key)
        return HStack(alignment: .top, spacing: CarveSpacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? CarveColor.accent : CarveColor.divider, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(CarveColor.accent)
                        .frame(width: 22, height: 22)
                    CarveIcon.checkmark.image
                        .resizable()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(CarveColor.surface)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CarveSpacing.xxSmall) {
                Text(Self.referenceText(favorite.key, showsTranslation: false, locale: locale))
                    .font(CarveTypography.body)
                    .foregroundStyle(CarveColor.ink)
                Text(favorite.key.translation.displayName(locale: locale))
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

    /// 「시편 23장 1절 · KJV」 · 「Psalm 23:1 · KJV」 — 화면 언어의 참조(`BibleReference`, 영어 현지화 결정 3 · 11). 뷰는 환경 `locale` 을 넘긴다.
    /// 담긴 말씀 목록은 번역본이 섞여 약칭을 붙이고, 고르기 시트는 약칭을 아랫줄에 따로 적어 붙이지 않는다.
    static func referenceText(_ key: FavoriteVerseKey, showsTranslation: Bool, locale: Locale) -> String {
        BibleReference(chapter: key.chapter, verse: key.verse, showsTranslation: showsTranslation).text(locale: locale)
    }
}
