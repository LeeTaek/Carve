//
//  CarveSurface.swift
//  UIComponents
//
//  Created by Claude on 9/11/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import SwiftUI

/// 표면 용도. 유리 · 불투명 분기를 화면마다 흩지 않고 이 한곳에서 정한다(문서 4-2).
///
/// 배포 타깃(iOS 17)은 올리지 않으므로 유리 표면과 불투명 표면이 **둘 다 출시된다.** 불투명 쪽은
/// "유리가 빠진 모습" 이 아니라 그 자체로 완성된 표면(`surface`)이다.
public enum CarveSurfaceStyle: Sendable {
    /// 종이 위에 떠 있는 조작 요소 — 헤더 버튼 · 도구 팔레트 · 접힘 버튼. iOS 26 이상은 유리.
    case floatingControl
    /// 내용을 담는 표면 — 탐색 오버레이 · 카드. iOS 26 이상은 유리.
    case panel
    /// 확인 대화상자 · 알림처럼 대비가 먼저인 표면. 항상 불투명하다.
    case solid
}

/// 컨트롤이 놓인 바탕. 버튼 · 세그먼트가 이 값으로 자기 바탕색을 고른다.
enum CarveBackdrop: Sendable {
    /// 화면 바탕(`canvas`) 위. 컨트롤 바탕은 `surface`.
    case canvas
    /// 표면 안. 컨트롤 바탕은 `fill`.
    case surface

    /// 이 바탕에 놓인 컨트롤의 바탕색.
    var controlFill: Color {
        switch self {
        case .canvas: CarveColor.surface
        case .surface: CarveColor.fill
        }
    }
}

private struct CarveBackdropKey: EnvironmentKey {
    static let defaultValue = CarveBackdrop.canvas
}

extension EnvironmentValues {
    var carveBackdrop: CarveBackdrop {
        get { self[CarveBackdropKey.self] }
        set { self[CarveBackdropKey.self] = newValue }
    }
}

public extension View {
    /// 표면 규격으로 배경을 깐다.
    ///
    /// iOS 26 이상은 유리, 그 밖에는 불투명 `surface` 에 1pt 구분선이다. 투명도 줄이기 · 대비 늘리기가 켜지면
    /// iOS 26 이상도 불투명으로 떨어진다(문서 4-3). 안쪽 컨트롤은 표면 안에 놓인 것으로 그려진다.
    /// - Parameters:
    ///   - style: 표면 용도.
    ///   - shape: 표면 모양.
    func carveSurface<S: Shape>(_ style: CarveSurfaceStyle, in shape: S) -> some View {
        modifier(CarveSurfaceModifier(style: style, shape: shape))
    }

    /// 팝오버 · 시트의 **내용**에 붙인다.
    ///
    /// 시스템 팝오버는 iOS 26 이상에서 이미 유리라 그대로 두고, 그 밖의 경로와 투명도 줄이기 · 대비 늘리기에서는
    /// 불투명 `surface` 로 칠한다. 안쪽 컨트롤은 표면 안에 놓인 것으로 그려진다.
    func carvePresentationSurface() -> some View {
        modifier(CarvePresentationSurfaceModifier())
    }
}

/// 유리를 쓸 수 있는 접근성 조건. 투명도 줄이기 · 대비 늘리기에서는 불투명 표면이다.
private func allowsGlass(reduceTransparency: Bool, contrast: ColorSchemeContrast) -> Bool {
    !reduceTransparency && contrast != .increased
}

private struct CarveSurfaceModifier<S: Shape>: ViewModifier {
    let style: CarveSurfaceStyle
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let content = content.environment(\.carveBackdrop, .surface)
        if #available(iOS 26.0, *), usesGlass {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(opaqueFill, in: shape)
                .overlay {
                    shape.stroke(CarveColor.divider, lineWidth: 1)
                }
        }
    }

    private var usesGlass: Bool {
        style != .solid && allowsGlass(reduceTransparency: reduceTransparency, contrast: contrast)
    }

    /// 확인 대화상자 · 알림은 라이트에서 종이색, 다크에서 표면색으로 떠오른다(시안 F2 · G2).
    private var opaqueFill: Color {
        style == .solid && colorScheme == .light ? CarveColor.canvas : CarveColor.surface
    }
}

private struct CarvePresentationSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let content = content.environment(\.carveBackdrop, .surface)
        if #available(iOS 26.0, *), allowsGlass(reduceTransparency: reduceTransparency, contrast: contrast) {
            content
        } else {
            content.presentationBackground(CarveColor.surface)
        }
    }
}
