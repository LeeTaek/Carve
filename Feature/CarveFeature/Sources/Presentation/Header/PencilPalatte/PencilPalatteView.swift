//
//  PencilPalatteView.swift
//  FeatureCarve
//
//  Created by 이택성 on 6/13/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import PencilKit
import SwiftUI

import ComposableArchitecture

@ViewAction(for: PencilPalatteFeature.self)
public struct PencilPalatteView: View {
    @Bindable public var store: StoreOf<PencilPalatteFeature>
    private let iconSize: CGFloat = 25
    private var iconBox: CGFloat { PencilPalatteMetrics.iconBox }

    public init(store: StoreOf<PencilPalatteFeature>) {
        self.store = store
    }

    /// 가용 폭에 맞춰 여백 단계를 고른다 (R22). 계산은 `PencilPalatteMetrics` 에 있다.
    private func metrics(for width: CGFloat) -> PencilPalatteMetrics {
        PencilPalatteMetrics.fit(
            in: width,
            penTypeCount: 4,
            lineWidthCount: store.lineWidths.count,
            colorCount: store.palatteColors.count
        )
    }

    public var body: some View {
        // 폭을 재서 배치를 고른다. 콘텐츠가 아니라 **컨테이너** 폭을 재므로 되먹임이 없다.
        GeometryReader { proxy in
            let metrics = metrics(for: proxy.size.width)

            if metrics.needsScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    row(metrics)
                }
                .frame(width: proxy.size.width)
            } else {
                row(metrics)
                    .frame(width: proxy.size.width, alignment: .center)
            }
        }
        // ⚠️ 선언 높이는 **종전 값을 그대로 둔다.** 실제 콘텐츠(35pt 아이콘 + 상하 여백)가 더 크지만,
        //    화면에서 본문과 겹치는 것이 관측된 적이 없다. 그리고 이 값이 `setHeaderHeight` 를 거쳐
        //    본문 상단 여백(`CarveDetailView` 의 `.padding(.top, headerHeight)`)이 되므로, 정직하게
        //    올리면 필사 화면의 세로 공간이 그만큼 줄어든다. R22 는 폭 문제이고 높이는 별건이라
        //    UI-1 에서 건드리지 않는다. 선언/렌더 불일치는 알려진 상태로 남긴다.
        .frame(height: 20)
        .padding(.bottom, 10)
    }

    private func row(_ metrics: PencilPalatteMetrics) -> some View {
        HStack(spacing: 0) {
            penTypePalatte(metrics)
            divider(metrics)
            penLineWidth(metrics)
            divider(metrics)
            colorPalatte(metrics)
            divider(metrics)
            doButtons(metrics)
        }
    }

    private func colorPalatte(_ metrics: PencilPalatteMetrics) -> some View {
        HStack(spacing: PencilPalatteMetrics.itemSpacing) {
            ForEach(Array(store.palatteColors.enumerated()), id: \.offset) { index, color in
                let isSelected = index == store.selectedColorIndex
                Circle()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(Color(uiColor: color.color))
                    .opacity(0.8)
                    .scaleEffect(isSelected ? 0.8 : 1)
                    .overlay {
                        Circle()
                            .stroke(lineWidth: 3)
                            .foregroundStyle(isSelected ? .gray.opacity(0.3) : .clear)
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, PencilPalatteMetrics.verticalPadding)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        send(.setColor(index))
                    }
                    .gesture(
                        longPressGesture(action: .popoverColor(index))
                    )
                    .accessibilityElement()
                    .accessibilityLabel("색상 \(index + 1)")
                    .accessibilityHint("길게 누르면 색을 바꿉니다")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: value.location.x,
                                    y: value.location.y)
                send(.setPopoverPoint(point))
            }
        )
        .popover(
            item: $store.scope(state: \.navigation?.colorPalatte,
                               action : \.navigation.colorPalatte),
            attachmentAnchor: .rect(.rect(CGRect(x: store.popoverPoint.x, y: iconBox, width: 0, height: 0)))
        ) { store in
            ColorPalatteView(store: store)
        }
    }

    private func divider(_ metrics: PencilPalatteMetrics) -> some View {
        Rectangle()
            .frame(width: 1, height: iconSize)
            .foregroundStyle(.gray)
            .padding(.horizontal, metrics.dividerPadding)
            .accessibilityHidden(true)
    }

    private func penLineWidth(_ metrics: PencilPalatteMetrics) -> some View {
        HStack(spacing: PencilPalatteMetrics.itemSpacing) {
            ForEach(Array(store.lineWidths.enumerated()), id: \.offset) { index, width in
                let isSelected = index == store.selectedWidthIndex
                RoundedRectangle(cornerRadius: 20)
                    .frame(width: iconBox, height: iconBox)
                    .foregroundStyle(isSelected ? .gray.opacity(0.3) : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .frame(width: iconBox, height: width)
                            .foregroundStyle(.black)
                            .scaleEffect(isSelected ? 0.8 : 1)
                            .opacity(isSelected ? 1 : 0.6)
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, PencilPalatteMetrics.verticalPadding)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        send(.setLineWidth(index))
                    }
                    .gesture(
                        longPressGesture(action: .popoverLineWidth(index))
                    )
                    .accessibilityElement()
                    .accessibilityLabel("선 굵기 \(index + 1)")
                    .accessibilityHint("길게 누르면 굵기를 바꿉니다")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: value.location.x,
                                    y: value.location.y)
                send(.setPopoverPoint(point))
            }
        )
        .popover(
            item: $store.scope(state: \.navigation?.lineWidthPalatte,
                               action : \.navigation.lineWidthPalatte),
            attachmentAnchor: .rect(.rect(CGRect(x: store.popoverPoint.x, y: iconBox, width: 0, height: 0)))
        ) { store in
            LineWidthPalatteView(store: store)
        }
    }

    private func penTypePalatte(_ metrics: PencilPalatteMetrics) -> some View {
        HStack(spacing: PencilPalatteMetrics.itemSpacing) {
            penTypeButton(.pencil, label: "연필", asset: CarveFeatureAsset.pencilType, metrics: metrics)
            penTypeButton(.pen, label: "펜", asset: CarveFeatureAsset.penType, metrics: metrics)
            penTypeButton(.marker, label: "형광펜", asset: CarveFeatureAsset.pencilHighlighter, metrics: metrics)
            penTypeButton(.monoline, label: "지우개", asset: CarveFeatureAsset.eraserType, metrics: metrics)
        }
    }

    private func penTypeButton(
        _ type: PKInkingTool.InkType,
        label: String,
        asset: CarveFeatureImages,
        metrics: PencilPalatteMetrics
    ) -> some View {
        let isSelected = store.pencilConfig.pencilType == type
        return RoundedRectangle(cornerRadius: 20)
            .frame(width: iconBox, height: iconBox)
            .foregroundStyle(isSelected ? .gray.opacity(0.3) : .clear)
            .overlay {
                asset.swiftUIImage
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(isSelected ? 0.8 : 1)
                    .opacity(isSelected ? 1 : 0.6)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, PencilPalatteMetrics.verticalPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                send(.setPencilType(type))
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func doButtons(_ metrics: PencilPalatteMetrics) -> some View {
        HStack(spacing: PencilPalatteMetrics.itemSpacing) {
            Button {
                send(.undo)
            } label: {
                CarveFeatureAsset.undo.swiftUIImage
                    .resizable()
                    .frame(width: iconBox, height: iconBox)
                    .opacity(store.canUndo ? 1 : 0.3)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, PencilPalatteMetrics.verticalPadding)
            }
            .disabled(!store.canUndo)
            .accessibilityLabel("실행 취소")

            Button {
                send(.redo)
            } label: {
                CarveFeatureAsset.redo.swiftUIImage
                    .resizable()
                    .frame(width: iconBox, height: iconBox)
                    .opacity(store.canRedo ? 1 : 0.3)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, PencilPalatteMetrics.verticalPadding)
            }
            .disabled(!store.canRedo)
            .accessibilityLabel("다시 실행")
        }
    }

    private func longPressGesture(action: PencilPalatteFeature.Action.View) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                send(action)
            }
    }
}
