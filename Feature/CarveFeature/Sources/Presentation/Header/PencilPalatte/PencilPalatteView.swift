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
/// 올가미는 선택한 필기를 옮기는 도구다 — 잉크 종류가 아니라 `isLassoSelected` 가 펜 · 지우개보다 우선한다 (올가미 설계 §4-1).
/// 표면(유리)은 `PencilPalatteDockView` 가 깐다.
@ViewAction(for: PencilPalatteFeature.self)
public struct PencilPalatteView: View {
    @Bindable public var store: StoreOf<PencilPalatteFeature>
    /// 화면 언어 — 도구 이름 · 버튼 접근성 이름을 이 값으로 만든다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale

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
        !store.isLassoSelected && store.pencilConfig.pencilType == .monoline
    }

    /// 잉크로 쓰는 중인가 — 펜 칸의 선택 표시.
    private var isInking: Bool {
        !store.isLassoSelected && store.pencilConfig.pencilType != .monoline
    }

    /// 펜 칸이 가리키는 잉크. 지우개를 쓰는 중이면 마지막으로 고른 잉크다.
    private var activeInk: PKInkingTool.InkType {
        isErasing ? store.lastInkType : store.pencilConfig.pencilType
    }

    private var toolButtons: some View {
        HStack(spacing: CarveSpacing.xxSmall) {
            CarveIconButton(.pen, accessibilityLabel: inkName(activeInk), isSelected: isInking, background: .plain) {
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
            .accessibilityHint(Text("길게 누르면 연필 · 펜 · 형광펜을 고릅니다", bundle: .module))

            CarveIconButton(.eraser, accessibilityLabel: CarveFeatureCatalog.string("지우개", locale: locale), isSelected: isErasing, background: .plain) {
                send(.setPencilType(.monoline))
            }

            CarveIconButton(
                .lasso,
                accessibilityLabel: CarveFeatureCatalog.string("올가미", locale: locale),
                isSelected: store.isLassoSelected,
                background: .plain
            ) {
                send(.selectLasso)
            }
            .accessibilityHint(Text("필기를 묶어 옮깁니다", bundle: .module))
        }
    }

    private func inkName(_ ink: PKInkingTool.InkType) -> String {
        switch ink {
        case .pencil: CarveFeatureCatalog.string("연필", locale: locale)
        case .marker: CarveFeatureCatalog.string("형광펜", locale: locale)
        default: CarveFeatureCatalog.string("펜", locale: locale)
        }
    }

    // MARK: - 굵기

    private func millimeters(_ lineWidth: CGFloat) -> String {
        String(format: "%.1f mm", lineWidth / 4)
    }

    /// 현재 굵기 글자(시안 「0.5 mm」). 탭하면 시안 P2 「펜 굵기」 팝오버를 연다.
    ///
    /// 예전에는 여기서 굵기 칸 목록을 먼저 띄우고 「조절」 을 눌러야 값 편집으로 갔다. 팝오버 두 개가
    /// 겹치지 않도록 0.35초를 기다려 여는 임시 처리까지 있었는데, P2 가 고르기와 조절을 한 화면에 담아
    /// 그 단계를 없앴다 (디자인 문서 5장 — 「팝오버는 한 번에 하나만 연다」).
    private var lineWidthButton: some View {
        Button {
            send(.popoverLineWidth(store.editingWidthIndex))
        } label: {
            Text(millimeters(store.pencilConfig.lineWidth))
                .font(CarveTypography.body)
                .monospacedDigit()
                .foregroundStyle(CarveColor.ink)
                // 팔레트는 시안 크기(504 × 64)로 고정이라 큰 글자에서 이 글자가 색 칸을 덮었다(2026-10-13). 열 라벨 줄과 같이
                // 시스템 최대 글자(xxxLarge)까지만 키우고, 그래도 넘치면 남은 자리에 맞춰 줄인다 — 자리는 아래 `layoutPriority` 가 먼저 받는다.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(minWidth: CarveSize.minimumHitTarget, minHeight: CarveSize.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 뒤의 `Spacer` 와 자리를 나누지 않고 글자 폭을 먼저 받는다(전에는 `fixedSize` 로 늘 제 폭이었다).
        .layoutPriority(1)
        .accessibilityLabel(Text("펜 굵기 \(millimeters(store.pencilConfig.lineWidth))", bundle: .module))
        .accessibilityHint(Text("탭하면 굵기를 고릅니다", bundle: .module))
        .popover(
            item: $store.scope(state: \.navigation?.lineWidthPalatte,
                               action: \.navigation.lineWidthPalatte),
            arrowEdge: .bottom
        ) { store in
            LineWidthPalatteView(store: store)
        }
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
                    .accessibilityLabel(Text("색상 \(index + 1)", bundle: .module))
                    .accessibilityHint(Text("길게 누르면 색을 바꿉니다", bundle: .module))
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
            CarveIconButton(.undo, accessibilityLabel: CarveFeatureCatalog.string("실행 취소", locale: locale), background: .plain) {
                send(.undo)
            }
            .disabled(!store.canUndo)

            CarveIconButton(.redo, accessibilityLabel: CarveFeatureCatalog.string("다시 실행", locale: locale), background: .plain) {
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

/// 도크 안(팔레트 유리 · 실행 취소 · 안내 줄)의 identity. 필사 화면을 떠났다가(앱 스택에 책장 · 차트 · 즐겨찾기가 올라와
/// 창에서 빠짐) 다시 나타나면 새 값이 되어 `PencilPalatteDockView` 가 안을 새로 만든다. 처음 나타날 때는 그대로다.
///
/// 순수 상태라 UI 없이 시험한다(`PencilPalatteDockIdentityTesting`).
struct PencilPalatteDockIdentity: Equatable {
    /// 뷰의 `.id` 로 쓰는 값. 떠났다가 돌아올 때마다 하나씩 는다.
    private(set) var generation = 0
    /// 화면에서 사라진 뒤 아직 다시 나타나지 않았다.
    private(set) var isAway = false

    /// 화면에서 사라졌다.
    mutating func disappeared() {
        isAway = true
    }

    /// 화면에 나타났다. 떠났다가 돌아온 것이면 새 identity 로 바꾸고 true, 아니면(처음 나타남 · 거듭 불림) 그대로 두고 false.
    @discardableResult
    mutating func appeared() -> Bool {
        guard isAway else { return false }
        isAway = false
        generation += 1
        return true
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
    /// 화면 언어 — 도구 이름 · 조작 안내 · 실행 취소 접근성 이름을 이 값으로 만든다(즉시 전환 단계 3).
    @Environment(\.locale) private var locale
    /// 손가락 필사 허용(본문 설정). 펼친 팔레트 아래 조작 안내가 이 값을 따른다.
    @Shared(.appStorage("allowFingerDrawing")) private var allowFingerDrawing: Bool = false
    /// 화면에 그리는 펼침 상태. 리듀서가 바꾼 `isExpanded` 를 `withAnimation` 으로 옮겨 받아 폭 변화를 한 트랜잭션으로 묶는다.
    @State private var isShowingExpanded: Bool
    /// 도크 안(팔레트 유리 · 실행 취소 · 안내 줄)의 identity — 필사 화면을 떠났다가 돌아오면 바뀐다(`body` 의 ⚠️).
    @State private var identity = PencilPalatteDockIdentity()

    /// 접힌 도구 원 아래 「펜 · 0.5 mm」 줄 높이.
    private static let captionHeight: CGFloat = 16
    /// 도크 전체 높이 — 맨 위 도구 줄(64) · 도구 이름 줄 · 아래 여백. 도크 곁에 뜨는 안내(즐겨찾기 결과)가 이 값으로 자리를 잡는다.
    static let height: CGFloat = CarveSize.floatingToolButton + CarveSpacing.xxSmall + captionHeight + CarveSpacing.small

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
            VStack(alignment: sideAlignment, spacing: CarveSpacing.xxSmall) {
                HStack(spacing: isShowingExpanded ? 0 : CarveSpacing.medium) {
                    if isLeftHanded { undoButton }
                    paletteSurface(expandedWidth: expandedWidth)
                    if !isLeftHanded { undoButton }
                }
                caption(expandedWidth: expandedWidth)
            }
            .frame(maxWidth: .infinity, alignment: isShowingExpanded ? .center : Alignment(horizontal: sideAlignment, vertical: .center))
            .padding(.horizontal, CarveSpacing.large)
        }
        // ⚠️ 필사 화면을 떠났다가 돌아오면 도크 안을 새로 만든다. 펼침 · 접힘 전환(폭 애니메이션)이 진행 중일 때 앱 스택에 책장이 올라가
        //    필사 화면이 창에서 빠지고, 책장 위에 이름 시트가 떴다 닫힌 뒤(키보드와 무관) 돌아오면, 멈춰 있던 애니메이션이 이어지다
        //    한 프레임에 폭이 ±1e18 로 튀었다(iOS 26.2 시뮬레이터, 2026-10-16 — docs/notebook-design.md §9-2). 음수 폭을 받은 유리 안쪽 뷰
        //    (`UIPlatformGlassInteractionView`)는 그 폭을 bounds 원점에 쌓아, 폭이 504 로 돌아온 뒤에도 원점이 약 −5e18 에 남았다 —
        //    유리와 도구가 다시 그려지지 않았다. 새 identity 는 멈춰 있던 애니메이션과 그 유리를 함께 버린다. 처음 나타날 때는 그대로다.
        .id(identity.generation)
        .frame(height: Self.height)
        .onDisappear {
            identity.disappeared()
        }
        .onAppear {
            // 옛 도크가 들어오는 화면 전환에 섞여 사라지는 애니메이션을 타지 않게, 애니메이션 없이 바꾼다.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                identity.appeared()
            }
        }
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

    /// 접힘 상태의 실행 취소. 펼치면 크기 0으로 줄어들고, 접히면 현재 도구와 분리된 단일 버튼으로 나타난다.
    ///
    /// ⚠️ 펼친 동안에는 유리를 빼(`.plain`) 일반 뷰로 숨긴다. 유리 컨테이너는 유리 **안의 내용**을 따로 그려
    ///    바깥의 `opacity` · `scaleEffect` 를 따르지 않으므로, 유리를 둔 채 숨기면 캡슐 옆에 아이콘이 그대로 보였다.
    ///    접을 때 유리가 다시 생기며 독립된 버튼으로 나타난다.
    private var undoButton: some View {
        CarveIconButton(
            .undo,
            accessibilityLabel: CarveFeatureCatalog.string("실행 취소", locale: locale),
            background: isShowingExpanded ? .plain : .floating
        ) {
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
    ///
    /// 도크 높이가 고정(`height`)이라 큰 글자에서 안내가 팔레트 폭을 넘어 본문 위로 크게 겹쳤다(2026-10-13). 열 라벨 줄과 같이
    /// 시스템 최대 글자(xxxLarge)까지만 키우고, 펼친 안내는 팔레트 폭에 맞춰 줄인다. 접힌 줄은 짧아 전처럼 제 폭으로 원 아래 가운데에 둔다.
    private func caption(expandedWidth: CGFloat) -> some View {
        ZStack {
            if isShowingExpanded {
                Text(gestureGuide)
                    .minimumScaleFactor(0.7)
                    .transition(.opacity)
            } else {
                Text(verbatim: "\(compactToolName) · \(LineWidthPalatteView.millimeters(store.pencilConfig.lineWidth))")
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .font(CarveTypography.caption)
        .foregroundStyle(CarveColor.secondary)
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(
            width: isShowingExpanded ? expandedWidth : CarveSize.floatingToolButton,
            height: Self.captionHeight
        )
        .accessibilityHidden(true)
    }

    /// 펼친 팔레트 아래 조작 안내. 손가락 필사를 허용하면 한 손가락은 필기라 스크롤은 두 손가락이 된다.
    private var gestureGuide: String {
        allowFingerDrawing
            ? CarveFeatureCatalog.string("두 손가락으로 스크롤 · 손가락으로 필사", locale: locale)
            : CarveFeatureCatalog.string("손가락으로 스크롤 · Apple Pencil로 필사", locale: locale)
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
        .accessibilityLabel(Text("\(compactToolName), \(String(format: "%.1f", store.pencilConfig.lineWidth / 4)) 밀리미터. 탭하면 도구 팔레트를 펼칩니다", bundle: .module))
    }

    private var compactToolIcon: CarveIcon {
        if store.isLassoSelected { return .lasso }
        return store.pencilConfig.pencilType == .monoline ? .eraser : .pen
    }

    private var compactToolName: String {
        if store.isLassoSelected { return CarveFeatureCatalog.string("올가미", locale: locale) }
        switch store.pencilConfig.pencilType {
        case .monoline: return CarveFeatureCatalog.string("지우개", locale: locale)
        case .pencil: return CarveFeatureCatalog.string("연필", locale: locale)
        case .marker: return CarveFeatureCatalog.string("형광펜", locale: locale)
        default: return CarveFeatureCatalog.string("펜", locale: locale)
        }
    }
}
