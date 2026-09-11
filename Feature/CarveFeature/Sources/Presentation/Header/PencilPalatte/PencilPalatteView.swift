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
import UIComponents

/// 펼친 도구 팔레트의 한 줄(시안 M2 · J1). 504 × 64 안에 펜 · 지우개 · 올가미 | 굵기 | 색 셋 | 실행 취소 · 다시 실행.
///
/// 펜 칸 하나가 연필 · 펜 · 형광펜을 대표한다 — 길게 누르면 잉크를 고르고, 지우개에서 누르면 마지막 잉크로 돌아간다.
/// 올가미는 캔버스에 연결하기 전까지 비활성이다. 표면(유리)은 `PencilPalatteDockView` 가 깐다.
@ViewAction(for: PencilPalatteFeature.self)
public struct PencilPalatteView: View {
    @Bindable public var store: StoreOf<PencilPalatteFeature>
    @State private var isShowingWidthPicker = false

    /// 시안 M2 의 팔레트 크기.
    static let designWidth: CGFloat = 504
    static let designHeight: CGFloat = 64

    private static let inkTypes: [PKInkingTool.InkType] = [.pencil, .pen, .marker]

    public init(store: StoreOf<PencilPalatteFeature>) {
        self.store = store
    }

    public var body: some View {
        // 창이 시안 폭보다 좁을 때만 가로로 넘긴다(R22). 콘텐츠가 아니라 컨테이너 폭을 재므로 되먹임이 없다.
        GeometryReader { proxy in
            if proxy.size.width < Self.designWidth {
                ScrollView(.horizontal, showsIndicators: false) {
                    row
                }
            } else {
                row
                    .frame(width: proxy.size.width)
            }
        }
        .frame(height: Self.designHeight)
    }

    /// 시안 M2 의 x 좌표(팔레트 왼쪽 기준): 도구 12…152 · 굵기 176 · 색 중심 280 / 316 / 352 · 실행 취소 396 · 다시 실행 444 · 오른쪽 여백 16.
    private var row: some View {
        HStack(spacing: 0) {
            toolButtons
            lineWidthButton
                .padding(.leading, CarveSpacing.large)
            Spacer(minLength: CarveSpacing.medium)
            colorSwatches
            undoRedoButtons
                .padding(.leading, 26)
        }
        .padding(.leading, CarveSpacing.small)
        .padding(.trailing, CarveSpacing.medium)
        .frame(width: Self.designWidth, height: Self.designHeight)
    }

    // MARK: - 도구

    private var isErasing: Bool {
        store.pencilConfig.pencilType == .monoline
    }

    /// 펜 칸이 가리키는 잉크. 지우개를 쓰는 중이면 마지막으로 고른 잉크다.
    private var activeInk: PKInkingTool.InkType {
        isErasing ? store.lastInkType : store.pencilConfig.pencilType
    }

    private var toolButtons: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            CarveIconButton(.pen, accessibilityLabel: inkName(activeInk), isSelected: !isErasing, background: .plain) {
                send(.setPencilType(activeInk))
            }
            .contextMenu {
                ForEach(Self.inkTypes, id: \.self) { ink in
                    Button {
                        send(.setPencilType(ink))
                    } label: {
                        if ink == activeInk {
                            Label(inkName(ink), systemImage: "checkmark")
                        } else {
                            Text(inkName(ink))
                        }
                    }
                }
            }
            .accessibilityHint("길게 누르면 연필 · 펜 · 형광펜을 고릅니다")

            CarveIconButton(.eraser, accessibilityLabel: "지우개", isSelected: isErasing, background: .plain) {
                send(.setPencilType(.monoline))
            }

            CarveIconButton(.lasso, accessibilityLabel: "올가미", background: .plain) {}
                .disabled(true)
        }
    }

    private func inkName(_ ink: PKInkingTool.InkType) -> String {
        switch ink {
        case .pencil: "연필"
        case .marker: "형광펜"
        default: "펜"
        }
    }

    // MARK: - 굵기

    private func millimeters(_ lineWidth: CGFloat) -> String {
        String(format: "%.1f mm", lineWidth / 4)
    }

    /// 현재 굵기 글자(시안 「0.5 mm」). 탭하면 굵기 세 단계 중에서 고른다.
    private var lineWidthButton: some View {
        Button {
            isShowingWidthPicker = true
        } label: {
            Text(millimeters(store.pencilConfig.lineWidth))
                .font(CarveTypography.body)
                .monospacedDigit()
                .foregroundStyle(CarveColor.ink)
                .fixedSize()
                .frame(minWidth: CarveSize.minimumHitTarget, minHeight: CarveSize.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("펜 굵기 \(millimeters(store.pencilConfig.lineWidth))")
        .accessibilityHint("탭하면 굵기를 고릅니다")
        .popover(isPresented: $isShowingWidthPicker, arrowEdge: .bottom) {
            lineWidthPicker
        }
        // 굵기 값 편집은 기존 팝오버를 쓴다. 위의 선택 팝오버와 한 뷰에 겹치지 않게 배경에 단다.
        .background {
            Color.clear
                .popover(
                    item: $store.scope(state: \.navigation?.lineWidthPalatte,
                                       action: \.navigation.lineWidthPalatte),
                    arrowEdge: .bottom
                ) { store in
                    LineWidthPalatteView(store: store)
                }
        }
    }

    private var lineWidthPicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.lineWidths.enumerated()), id: \.offset) { index, width in
                lineWidthRow(index: index, width: width)
                if index < store.lineWidths.count - 1 {
                    CarveDivider()
                }
            }
        }
        .padding(.vertical, CarveSpacing.xSmall)
        .frame(width: 260)
        .carvePresentationSurface()
        .presentationCompactAdaptation(.popover)
    }

    private func lineWidthRow(index: Int, width: CGFloat) -> some View {
        let isSelected = index == store.selectedWidthIndex
        return HStack(spacing: CarveSpacing.small) {
            Button {
                send(.setLineWidth(index))
                isShowingWidthPicker = false
            } label: {
                HStack(spacing: CarveSpacing.small) {
                    Capsule()
                        .fill(CarveColor.ink)
                        .frame(width: 36, height: max(1, width))
                    Text(millimeters(width))
                        .font(CarveTypography.body)
                        .monospacedDigit()
                        .foregroundStyle(CarveColor.ink)
                    Spacer(minLength: 0)
                    if isSelected {
                        CarveIcon.checkmark.image
                            .foregroundStyle(CarveColor.accent)
                    }
                }
                .frame(minHeight: CarveSize.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("굵기 \(millimeters(width))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button("조절") {
                isShowingWidthPicker = false
                // 선택 팝오버가 닫힌 뒤에 편집 팝오버를 연다 — 팝오버 두 개가 동시에 뜨지 않게.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    send(.popoverLineWidth(index))
                }
            }
            .font(CarveTypography.label)
            .foregroundStyle(CarveColor.accent)
            .buttonStyle(.plain)
            .frame(minHeight: CarveSize.minimumHitTarget)
            .accessibilityLabel("\(millimeters(width)) 굵기 조절")
        }
        .padding(.horizontal, CarveSpacing.medium)
    }

    // MARK: - 색

    private var colorSwatches: some View {
        HStack(spacing: 0) {
            ForEach(Array(store.palatteColors.enumerated()), id: \.offset) { index, color in
                let isSelected = index == store.selectedColorIndex
                CarveColorSwatch(Color(uiColor: color.color), isSelected: isSelected)
                    .frame(width: 36, height: CarveSize.minimumHitTarget)
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
                send(.setPopoverPoint(value.location))
            }
        )
        .popover(
            item: $store.scope(state: \.navigation?.colorPalatte,
                               action: \.navigation.colorPalatte),
            attachmentAnchor: .rect(.rect(CGRect(x: store.popoverPoint.x, y: 0, width: 0, height: 0)))
        ) { store in
            ColorPalatteView(store: store)
        }
    }

    // MARK: - 실행 취소

    private var undoRedoButtons: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            CarveIconButton(.undo, accessibilityLabel: "실행 취소", background: .plain) {
                send(.undo)
            }
            .disabled(!store.canUndo)

            CarveIconButton(.redo, accessibilityLabel: "다시 실행", background: .plain) {
                send(.redo)
            }
            .disabled(!store.canRedo)
        }
    }

    private func longPressGesture(action: PencilPalatteFeature.Action.View) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                send(action)
            }
    }
}

/// 필사 화면 하단의 도구 팔레트. 펼침 상태는 전체 도구를, 접힘 상태는 현재 도구와 실행 취소를 남긴다.
///
/// ⚠️ 유리 뷰를 상태마다 넣고 빼지 않는다. 펼침 캡슐과 접힘 원을 `if` 로 갈아 끼우던 구조(glassEffectID morph)는
///    스크롤 이벤트가 이어지는 동안 전환이 끊기면 유리 **안의 내용**이 이동하던 자리에 남아, 유리와 아이콘이 어긋났다
///    (iOS 26.2 시뮬레이터에서 원 · 실행 취소 모두 재현). 그래서 팔레트 유리 하나를 계속 두고 **폭만** 64 ↔ 줄 폭으로 바꾸고
///    (폭과 높이가 같은 캡슐이 곧 원이다), 실행 취소는 크기를 0 으로 줄여 원 옆에서 사라지게 한다.
public struct PencilPalatteDockView: View {
    @Bindable public var store: StoreOf<PencilPalatteFeature>
    private let isExpanded: Bool
    private let isLeftHanded: Bool
    private let expand: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 화면에 그리는 펼침 상태. 리듀서가 바꾼 `isExpanded` 를 `withAnimation` 으로 옮겨 받아 폭 변화를 한 트랜잭션으로 묶는다.
    @State private var isShowingExpanded: Bool

    /// 접힌 도구 원 아래 「펜 · 0.5 mm」 줄 높이.
    private static let captionHeight: CGFloat = 16

    public init(
        store: StoreOf<PencilPalatteFeature>,
        isExpanded: Bool,
        isLeftHanded: Bool,
        expand: @escaping () -> Void
    ) {
        self.store = store
        self.isExpanded = isExpanded
        self.isLeftHanded = isLeftHanded
        self.expand = expand
        self._isShowingExpanded = State(initialValue: isExpanded)
    }

    public var body: some View {
        GeometryReader { proxy in
            // 펼친 팔레트는 시안 폭(504)이고, 창이 그보다 좁으면 가용 폭까지만 쓰고 안에서 넘긴다.
            let expandedWidth = min(max(0, proxy.size.width - CarveSpacing.large * 2), PencilPalatteView.designWidth)
            // iOS 26 유리에서는 가까운 유리끼리 붙었다 떨어진다 — 실행 취소가 원에서 갈라져 나오는 모양이 여기서 생긴다.
            // 그 밖의 경로 · 투명도 줄이기에서는 불투명 표면의 폭 · 크기 변화로 같은 전환을 한다.
            CarveSurfaceGroup(spacing: CarveSpacing.xLarge) {
                VStack(alignment: sideAlignment, spacing: CarveSpacing.xxSmall) {
                    HStack(spacing: isShowingExpanded ? 0 : CarveSpacing.small) {
                        if isLeftHanded { undoButton }
                        paletteSurface(expandedWidth: expandedWidth)
                        if !isLeftHanded { undoButton }
                    }
                    caption(expandedWidth: expandedWidth)
                }
                .frame(maxWidth: .infinity, alignment: isShowingExpanded ? .center : Alignment(horizontal: sideAlignment, vertical: .center))
            }
            .padding(.horizontal, CarveSpacing.large)
        }
        .frame(height: CarveSize.floatingToolButton + CarveSpacing.xxSmall + Self.captionHeight + CarveSpacing.small)
        .onChange(of: isExpanded) { _, newValue in
            withAnimation(transitionAnimation) {
                isShowingExpanded = newValue
            }
        }
    }

    /// 접힌 도구는 필기하는 손에서 먼 쪽 — 오른손은 왼쪽, 왼손은 오른쪽(문서 4-1).
    private var sideAlignment: HorizontalAlignment {
        isLeftHanded ? .trailing : .leading
    }

    /// 늘어날 때 끝에서 살짝 넘쳤다 돌아오는 탄성. 동작 줄이기에서는 짧은 전환으로 대신한다(문서 4-3).
    private var transitionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .bouncy(duration: 0.5, extraBounce: 0.15)
    }

    /// 팔레트 유리 모양. 펼치면 모서리 20 의 504 × 64(시안 M2), 접으면 64pt 원(시안 C3)이다. 모서리도 함께 이어서 바뀐다.
    private var paletteShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: isShowingExpanded ? CarveRadius.card : CarveSize.floatingToolButton / 2,
            style: .circular
        )
    }

    /// 팔레트 유리 하나. 폭과 모서리만 바뀐다.
    private func paletteSurface(expandedWidth: CGFloat) -> some View {
        ZStack {
            if isShowingExpanded {
                PencilPalatteView(store: store)
                    .transition(.opacity)
            } else {
                compactToolButton
                    .transition(.opacity)
            }
        }
        .frame(
            width: isShowingExpanded ? expandedWidth : CarveSize.floatingToolButton,
            height: CarveSize.floatingToolButton
        )
        // 늘어나는 동안 내용이 유리 밖으로 비어져 나오지 않게 유리 모양으로 자른다.
        .clipShape(paletteShape)
        .carveSurface(.floatingControl, in: paletteShape)
    }

    /// 접힘 상태의 실행 취소. 펼치면 원 옆에서 크기 0 으로 줄어들어 합쳐지고, 접으면 거기서 갈라져 나온다.
    ///
    /// ⚠️ 펼친 동안에는 유리를 빼(`.plain`) 일반 뷰로 숨긴다. 유리 컨테이너는 유리 **안의 내용**을 따로 그려
    ///    바깥의 `opacity` · `scaleEffect` 를 따르지 않으므로, 유리를 둔 채 숨기면 캡슐 옆에 아이콘이 그대로 보였다.
    ///    접을 때 유리가 다시 생기며 가까운 원에서 갈라져 나온다.
    private var undoButton: some View {
        CarveIconButton(.undo, accessibilityLabel: "실행 취소", background: isShowingExpanded ? .plain : .floating) {
            store.send(.view(.undo))
        }
        .disabled(!store.canUndo)
        .scaleEffect(isShowingExpanded ? 0.2 : 1, anchor: isLeftHanded ? .trailing : .leading)
        .opacity(isShowingExpanded ? 0 : 1)
        .frame(width: isShowingExpanded ? 0 : CarveSize.minimumHitTarget)
        .allowsHitTesting(!isShowingExpanded)
        .accessibilityHidden(isShowingExpanded)
    }

    /// 팔레트 아래 한 줄. 펼치면 조작 안내(시안 M2), 접으면 현재 도구와 굵기(시안 C3 「펜 · 0.5 mm」).
    private func caption(expandedWidth: CGFloat) -> some View {
        ZStack {
            if isShowingExpanded {
                Text("두 손가락으로 스크롤 · Apple Pencil로 필사")
                    .transition(.opacity)
            } else {
                Text("\(compactToolName) · \(store.pencilConfig.lineWidth / 4, specifier: "%.1f") mm")
                    .transition(.opacity)
            }
        }
        .font(CarveTypography.caption)
        .foregroundStyle(CarveColor.secondary)
        .lineLimit(1)
        .fixedSize()
        .frame(
            width: isShowingExpanded ? expandedWidth : CarveSize.floatingToolButton,
            height: Self.captionHeight
        )
        .accessibilityHidden(true)
    }

    private var compactToolButton: some View {
        Button(action: expand) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: store.pencilConfig.lineColor.color))
                    .frame(width: 8, height: 8)
                    .offset(x: 19, y: 19)
                compactToolIcon.image
                    .foregroundStyle(CarveColor.ink)
            }
            .frame(width: CarveSize.floatingToolButton, height: CarveSize.floatingToolButton)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(compactToolName), \(store.pencilConfig.lineWidth / 4, specifier: "%.1f") 밀리미터. 탭하면 도구 팔레트를 펼칩니다")
    }

    private var compactToolIcon: CarveIcon {
        store.pencilConfig.pencilType == .monoline ? .eraser : .pen
    }

    private var compactToolName: String {
        switch store.pencilConfig.pencilType {
        case .monoline: "지우개"
        case .pencil: "연필"
        case .marker: "형광펜"
        default: "펜"
        }
    }
}
