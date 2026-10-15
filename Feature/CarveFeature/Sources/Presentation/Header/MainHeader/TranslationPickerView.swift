//
//  TranslationPickerView.swift
//  CarveFeature
//
//  Created by Claude on 10/15/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import UIComponents

/// 헤더 제목을 누르면 뜨는 번역본 고르기(영어 현지화 결정 19). 본문 설정 · 펜 굵기와 같은 앱 팝오버 표면에 번역본 목록을 둔다.
///
/// 고르는 순간 그 번역본의 같은 권 · 장 · 보던 절로 가므로(결정 9) 「완료」 없이 바로 닫힌다. 표시 여부는 `HeaderFeature` 가 갖는다.
struct TranslationPickerView: View {
    /// 지금 번역본 — 선택 바탕 · 체크로 표시한다.
    let selection: Translation
    /// 번역본을 고름. 지금 번역본을 다시 골라도 부른다(닫기만 된다).
    let onSelect: (Translation) -> Void
    /// 화면 언어 — 제목 · 번역본 이름을 이 값으로 만든다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader(CarveFeatureCatalog.string("번역본", locale: locale))

            VStack(spacing: CarveSpacing.xxSmall) {
                ForEach(Translation.allCases, id: \.self) { translation in
                    row(translation)
                }
            }
            .padding(CarveSpacing.small)
        }
        .frame(width: 320)
        .carvePresentationSurface()
        .presentationCompactAdaptation(.popover)
    }

    /// 번역본 한 줄 — 약칭을 위에, 전체 이름을 아래에 적는다. 둘이 같으면(한국어의 개역개정) 한 줄이다.
    private func row(_ translation: Translation) -> some View {
        let isSelected = translation == selection
        let abbreviation = translation.displayName(locale: locale)
        let fullName = translation.fullName(locale: locale)
        return Button {
            onSelect(translation)
        } label: {
            HStack(spacing: CarveSpacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: abbreviation)
                        .font(CarveTypography.body)
                        .foregroundStyle(CarveColor.ink)
                    if fullName != abbreviation {
                        // 다크에서 보조 글자는 선택 바탕 위 대비가 모자라다 — 고른 줄은 잉크로 쓴다(`VerseDrawingHistoryView` 와 같다).
                        Text(verbatim: fullName)
                            .font(CarveTypography.caption)
                            .foregroundStyle(isSelected ? CarveColor.ink : CarveColor.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    CarveIcon.checkmark.image
                        .resizable()
                        .frame(width: 17, height: 17)
                        .foregroundStyle(CarveColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, CarveSpacing.medium)
            .padding(.vertical, CarveSpacing.small)
            .frame(minHeight: CarveSize.minimumHitTarget)
            .background(
                isSelected ? CarveColor.selected : Color.clear,
                in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: HeaderView.translationMenuTitle(translation, locale: locale)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
