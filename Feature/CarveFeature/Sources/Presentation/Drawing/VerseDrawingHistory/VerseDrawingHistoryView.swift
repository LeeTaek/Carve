//
//  SentenceDrewHistoryListView.swift
//  FeatureCarve
//
//  Created by 이택성 on 7/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Domain
import SwiftUI
import PencilKit

import ComposableArchitecture
import UIComponents

/// 절의 이전 필사 기록(시안 E2 · E3) — 제목 줄 · 회차 목록 · 안내.
///
/// 회차를 누르면 곧바로 그 회차가 대표가 된다(탭 즉시 전환, 2026-09-10 결정). 되돌릴 수 있는 동작이라 확인 단계가 없다.
/// 지금 보이는 회차는 체크 · 「지금 보이는 회차」 · 행 바탕으로 색 말고도 구분한다.
/// 표면(팝오버 · 시트)은 감싸는 쪽이 정한다 — 단일 Canvas 는 `VerseHistoryPopover`, N-Canvas 는 시트다.
@ViewAction(for: VerseDrawingHistoryFeature.self)
public struct VerseDrawingHistoryView: View {
    @Bindable public var store: StoreOf<VerseDrawingHistoryFeature>

    public init(store: StoreOf<VerseDrawingHistoryFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            CarvePanelHeader("\(store.verse)절 · 이전 필사") {
                if store.hasLoaded {
                    Text("\(store.drawings.count)회")
                        .font(CarveTypography.label)
                        .foregroundStyle(CarveColor.secondary)
                }
            }

            content

            CarveDivider()
            VStack(alignment: .leading, spacing: 2) {
                Text("회차를 선택하면 바로 그 필사로 바뀌어요.")
                Text("다른 회차는 지워지지 않고 그대로 남아요.")
            }
            .font(CarveTypography.caption)
            .foregroundStyle(CarveColor.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CarveSpacing.large)
            .padding(.vertical, CarveSpacing.small)
        }
        .onAppear {
            send(.fetchDrawings)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.hasLoaded {
            // 조회 중 — 빈 상태로 깜빡이지 않도록 자리만 둔다.
            Color.clear.frame(height: 120)
        } else if store.drawings.isEmpty {
            CarveEmptyState(
                "아직 이 절의 이전 필사가 없어요.",
                message: "이전 필사 기록이 생기면 여기에 보여요."
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
            ForEach(store.drawings) { drawing in
                row(for: drawing)
            }
        }
        .padding(CarveSpacing.small)
    }

    @ViewBuilder
    private func row(for drawing: BibleDrawing) -> some View {
        let isCurrent = drawing.isPresent == true
        if let image = Self.thumbnail(of: drawing.lineData) {
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
            .accessibilityLabel(Self.dateText(drawing.updateDate) + (isCurrent ? ", 지금 보이는 회차" : ""))
            .accessibilityHint(isCurrent ? "" : "누르면 이 필사로 바뀌어요")
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
        } else {
            // 손상된 회차(시안 E3) — 이 회차만 건너뛰고 목록 전체를 막지 않는다.
            rowBody(drawing: drawing, isCurrent: isCurrent) {
                Text("불러올 수 없는 필사 데이터")
                    .font(CarveTypography.label)
                    .foregroundStyle(CarveColor.danger)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// 날짜 줄과 종이 카드. 지금 보이는 회차는 선택 바탕 · 체크로 표시한다.
    private func rowBody<Thumbnail: View>(
        drawing: BibleDrawing,
        isCurrent: Bool,
        @ViewBuilder thumbnail: () -> Thumbnail
    ) -> some View {
        VStack(alignment: .leading, spacing: CarveSpacing.xSmall) {
            HStack(spacing: CarveSpacing.xxSmall) {
                // 다크에서 보조 글자는 선택 바탕 위 대비가 모자라다(4.34:1) — 지금 회차의 날짜는 잉크로 쓴다.
                Text(Self.dateText(drawing.updateDate))
                    .foregroundStyle(isCurrent ? CarveColor.ink : CarveColor.secondary)
                Spacer(minLength: CarveSpacing.xSmall)
                if isCurrent {
                    CarveIcon.checkmark.image
                        .resizable()
                        .frame(width: 17, height: 17)
                    Text("지금 보이는 회차")
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

    /// 회차 썸네일 — 필기 범위를 고정 폭에 비율을 지켜 줄인다(시안 E2).
    ///
    /// 종이 위 필기라 라이트 외관으로 그린다. 다크 외관으로 그리면 PencilKit 이 잉크 색을 바꿔 저장된 색과 달라진다.
    static func thumbnail(of data: Data?) -> UIImage? {
        guard let data, let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds.insetBy(dx: -4, dy: -4)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: 2)
        }
        return image
    }

    static func dateText(_ date: Date?) -> String {
        guard let date else { return "날짜를 확인할 수 없어요" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { VerseDrawingHistoryFeature() }
    )
    VerseDrawingHistoryView(store: store)
}
