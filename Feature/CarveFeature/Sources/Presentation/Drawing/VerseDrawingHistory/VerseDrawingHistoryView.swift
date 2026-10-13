//
//  SentenceDrewHistoryListView.swift
//  FeatureCarve
//
//  Created by 이택성 on 7/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import ComposableArchitecture
import UIComponents

/// 절의 이전 필사 기록(시안 E2 · E3) — 제목 줄 · 회차 목록 · 안내.
///
/// 회차를 누르면 곧바로 그 회차가 대표가 된다(탭 즉시 전환, 2026-09-10 결정). 되돌릴 수 있는 동작이라 확인 단계가 없다.
/// 지금 보이는 회차는 체크 · 「지금 보이는 회차」 · 행 바탕으로 색 말고도 구분한다.
/// 표면은 감싸는 쪽이 정한다 — 필사 화면은 `VerseHistoryPopover` 다.
@ViewAction(for: VerseDrawingHistoryFeature.self)
public struct VerseDrawingHistoryView: View {
    @Bindable public var store: StoreOf<VerseDrawingHistoryFeature>
    /// 화면 언어 — 제목 · 날짜 줄 · 안내 · 접근성 이름을 이 값으로 만든다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

    public init(store: StoreOf<VerseDrawingHistoryFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader(CarveFeatureCatalog.string("\(store.verse)절 · 이전 필사", locale: locale)) {
                if store.hasLoaded {
                    Text("\(store.drawings.count)회", bundle: .module)
                        .font(CarveTypography.label)
                        .foregroundStyle(CarveColor.secondary)
                }
            }

            content

            CarveDivider()
            footer
        }
        .onAppear {
            send(.fetchDrawings)
        }
        .onChange(of: store.restoreBlock) { _, block in
            guard let block else { return }
            AccessibilityNotification.Announcement(Self.blockedMessage(block, locale: locale)).post()
        }
    }

    /// 아래 안내 — 쓰지 못하고 막았으면 그 사유를 그 자리에 보인다(정책 §12-6 결정 1). 다시 눌러도 같은 사유라 「다시 시도」 를 두지 않는다.
    @ViewBuilder
    private var footer: some View {
        if let block = store.restoreBlock {
            CarveStatusMessage(.failure, message: Self.blockedMessage(block, locale: locale))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CarveSpacing.large)
                .padding(.vertical, CarveSpacing.small)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("회차를 선택하면 바로 그 필사로 바뀌어요.", bundle: .module)
                Text("다른 회차는 지워지지 않고 그대로 남아요.", bundle: .module)
            }
            .font(CarveTypography.caption)
            .foregroundStyle(CarveColor.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CarveSpacing.large)
            .padding(.vertical, CarveSpacing.small)
        }
    }

    /// 역할: 회차를 바꾸지 않고 막은 안내 — 사유를 뒤에 붙인다.
    /// 입력 · 출력: 막은 사유 · 로케일(뷰는 환경 locale 을 넘긴다) → 문구.
    /// 부작용: 없음.
    static func blockedMessage(_ block: SyncedWriteBlock, locale: Locale) -> String {
        CarveFeatureCatalog.string("이 회차로 바꾸지 않았어요. \(block.reasonText(locale: locale))", locale: locale)
    }

    @ViewBuilder
    private var content: some View {
        if !store.hasLoaded {
            // 조회 중 — 빈 상태로 깜빡이지 않도록 자리만 둔다.
            Color.clear.frame(height: 120)
        } else if store.drawings.isEmpty {
            CarveEmptyState(
                CarveFeatureCatalog.string("아직 이 절의 이전 필사가 없어요.", locale: locale),
                message: CarveFeatureCatalog.string("이전 필사 기록이 생기면 여기에 보여요.", locale: locale)
            )
        } else {
            // 목록이 짧으면 내용 높이만큼, 길면 주어진 높이 안에서 스크롤한다.
            ViewThatFits(in: .vertical) {
                rows
                ScrollView { rows }
            }
        }
    }

    private var rows: some View {
        VStack(spacing: CarveSpacing.xxSmall) {
            ForEach(store.drawings, id: \.rowID) { drawing in
                row(for: drawing)
            }
        }
        .padding(CarveSpacing.small)
    }

    @ViewBuilder
    private func row(for drawing: VerseDrawingSnapshot) -> some View {
        let isCurrent = drawing.isPresent
        if let image = CarveInkThumbnail.image(of: drawing.lineData) {
            Button {
                send(.selectDrawing(drawing))
            } label: {
                rowBody(drawing: drawing, isCurrent: isCurrent) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 120)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.rowAccessibilityLabel(drawing.updateDate, isCurrent: isCurrent, locale: locale))
            .accessibilityHint(isCurrent ? Text(verbatim: "") : Text("누르면 이 필사로 바뀌어요", bundle: .module))
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
        } else {
            // 손상된 회차(시안 E3) — 이 회차만 건너뛰고 목록 전체를 막지 않는다.
            rowBody(drawing: drawing, isCurrent: isCurrent) {
                Text("불러올 수 없는 필사 데이터", bundle: .module)
                    .font(CarveTypography.label)
                    .foregroundStyle(CarveColor.danger)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// 날짜 줄과 종이 카드. 지금 보이는 회차는 선택 바탕 · 체크로 표시한다.
    private func rowBody<Thumbnail: View>(
        drawing: VerseDrawingSnapshot,
        isCurrent: Bool,
        @ViewBuilder thumbnail: () -> Thumbnail
    ) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            HStack(spacing: CarveSpacing.xxSmall) {
                // 다크에서 보조 글자는 선택 바탕 위 대비가 모자라다(4.34:1) — 지금 회차의 날짜는 잉크로 쓴다.
                Text(Self.dateText(drawing.updateDate, locale: locale))
                    .foregroundStyle(isCurrent ? CarveColor.ink : CarveColor.secondary)
                Spacer(minLength: CarveSpacing.xSmall)
                if isCurrent {
                    CarveIcon.checkmark.image
                        .resizable()
                        .frame(width: 17, height: 17)
                    Text("지금 보이는 회차", bundle: .module)
                }
            }
            .font(CarveTypography.caption)
            .foregroundStyle(CarveColor.accent)

            thumbnail()
                .padding(CarveSpacing.small)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(CarveColor.Paper.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(CarveSpacing.small)
        .background(
            isCurrent ? CarveColor.selected : Color.clear,
            in: RoundedRectangle(cornerRadius: CarveRadius.control, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    /// 역할: 회차 행의 VoiceOver 이름 — 날짜, 지금 보이는 회차면 그 사실을 함께 읽는다.
    /// 입력 · 출력: 회차 시각 · 지금 보이는 회차인가 · 로케일(뷰는 환경 locale 을 넘긴다) → 이름. 부작용: 없음.
    static func rowAccessibilityLabel(_ date: Date?, isCurrent: Bool, locale: Locale) -> String {
        let dateText = dateText(date, locale: locale)
        guard isCurrent else { return dateText }
        return "\(dateText), \(CarveFeatureCatalog.string("지금 보이는 회차", locale: locale))"
    }

    /// 역할: 회차의 날짜 줄(「2026년 9월 15일 오후 3:20」 · 「September 15, 2026 at 3:20 PM」).
    ///   고정 형식이 아니라 넘긴 로케일의 날짜 · 시각 서식(`Date.FormatStyle`)을 따른다(영어 현지화 결정 5).
    /// 입력 · 출력: 회차 시각(nil 이면 날짜를 모른다는 문구) · 로케일(뷰는 환경 locale 을 넘긴다) → 문구.
    /// 부작용: 없음.
    static func dateText(_ date: Date?, locale: Locale) -> String {
        guard let date else { return CarveFeatureCatalog.string("날짜를 확인할 수 없어요", locale: locale) }
        let style = Date.FormatStyle(locale: locale)
            .year()
            .month(.wide)
            .day()
            .hour()
            .minute()
        return date.formatted(style)
    }
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { VerseDrawingHistoryFeature() }
    )
    VerseDrawingHistoryView(store: store)
}
