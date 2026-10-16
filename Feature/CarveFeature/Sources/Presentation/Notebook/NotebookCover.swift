//
//  NotebookCover.swift
//  CarveFeature
//
//  Created by Claude on 10/16/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Domain
import SwiftUI

import UIComponents

/// 책장 표지의 모양 — 표지 색 · 선 삽화 · 번호(시안 `docs/design/assets/figma/p1-notebook-shelf.svg`).
///
/// - 번호는 이름이 서수 꼴일 때만 붙는다(「세 번째 필사」 → 03, `NotebookNaming.ordinal(inName:)`). 사용자가 지은 다른 이름은 번호 없이 큰 삽화다.
/// - 표지는 기기 · 실행마다 같아야 한다 — 번호가 있으면 번호로, 없으면 필사책 ID 의 고정 해시로 고른다. 목록 순서나 다른 필사책 지우기로 바뀌지 않는다.
///   (Swift `hashValue` 는 실행마다 달라 쓰지 않는다.)
struct NotebookCoverStyle: Equatable {
    let theme: NotebookCoverTheme
    /// 표지 번호 — 서수 꼴 이름의 서수. nil 이면 번호 없이 큰 삽화.
    let number: Int?

    /// 번호가 있는 표지의 순서 — 시안의 01(회색 · 산) · 02(따뜻한 회색 · 원) · 03(세이지 · 잎), 그 뒤로 돌아간다.
    private static let numberedOrder: [NotebookCoverTheme] = [.stone, .linen, .sage, .meadow, .sand]

    /// 역할: 필사책의 표지 모양을 정한다.
    /// 입력 · 출력: 필사책 · 로케일(보이는 이름) → 표지. 서수 꼴 이름이면 그 번호와 번호 순서의 표지, 아니면 ID 해시의 표지.
    /// 부작용: 없음.
    static func make(for notebook: NotebookSnapshot, locale: Locale) -> NotebookCoverStyle {
        let name = NotebookNaming.displayName(of: notebook, locale: locale)
        if let number = NotebookNaming.ordinal(inName: name) {
            return NotebookCoverStyle(theme: numberedOrder[(number - 1) % numberedOrder.count], number: number)
        }
        let index = Int(stableHash(notebook.id.rawValue) % UInt32(NotebookCoverTheme.allCases.count))
        return NotebookCoverStyle(theme: NotebookCoverTheme.allCases[index], number: nil)
    }

    /// 역할: 표지 번호 글자 — 두 자리로 채운다(1 → 「01」).
    /// 입력 · 출력: 서수 → 「01」 ~ 「99」, 100 이상은 그대로.
    /// 부작용: 없음.
    static func numberText(_ number: Int) -> String {
        number < 100 ? String(format: "%02d", number) : String(number)
    }

    /// 역할: 실행 · 기기와 상관없이 같은 값을 내는 문자열 해시(FNV-1a 32비트).
    /// 입력 · 출력: 문자열 → 해시.
    /// 부작용: 없음.
    static func stableHash(_ text: String) -> UInt32 {
        text.utf8.reduce(UInt32(2_166_136_261)) { hash, byte in
            (hash ^ UInt32(byte)) &* 16_777_619
        }
    }
}

/// 표지 다섯 가지 — 시안의 표지 색 · 책등 색 · 글자 색 · 선 삽화를 그대로 옮긴다. 표지는 책처럼 다크 화면에서도 같은 색이다.
enum NotebookCoverTheme: CaseIterable, Equatable {
    /// 회색 표지 · 산(시안 01).
    case stone
    /// 따뜻한 회색 표지 · 원(시안 02).
    case linen
    /// 세이지 표지 · 잎, 밝은 글자(시안 03).
    case sage
    /// 연한 세이지 표지 · 잎(시안 「시편 묵상」).
    case meadow
    /// 베이지 표지 · 아치(시안 「복음서 필사」).
    case sand

    var coverColor: Color {
        switch self {
        case .stone: Self.color(0xB9B8B1)
        case .linen: Self.color(0xDEDCD3)
        case .sage: Self.color(0x829383)
        case .meadow: Self.color(0xD8DFCE)
        case .sand: Self.color(0xEEE5D5)
        }
    }

    var spineColor: Color {
        switch self {
        case .stone: Self.color(0x979A92)
        case .linen: Self.color(0xC2C1B6)
        case .sage: Self.color(0x667B69)
        case .meadow: Self.color(0xB4C0AB)
        case .sand: Self.color(0xD5C9B6)
        }
    }

    /// 표지 위 글자 · 삽화 색. 세이지만 흰색이고 나머지는 시안의 먹색(라이트 `ink`)이다 — 표지 색이 고정이라 글자도 고정한다.
    var contentColor: Color {
        self == .sage ? .white : Self.color(0x303B36)
    }

    var illustration: NotebookCoverIllustration {
        switch self {
        case .stone: .mountains
        case .linen: .circles
        case .sage, .meadow: .leaf
        case .sand: .arch
        }
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// 표지의 선 삽화 — 시안 `defs` 의 경로를 그대로 옮긴다. 좌표는 삽화의 바닥 가운데(0, 0)에서 위로 음수다.
enum NotebookCoverIllustration: Equatable {
    case leaf
    case circles
    case mountains
    case arch

    /// 시안의 선 굵기(크기를 바꾸기 전).
    var lineWidth: CGFloat {
        self == .leaf ? 1.15 : 1.1
    }

    /// 역할: 삽화 경로를 바닥 가운데 `origin` · 배율 `scale` 로 놓는다.
    /// 입력 · 출력: 놓을 점 · 배율 → 경로.
    /// 부작용: 없음.
    func path(origin: CGPoint, scale: CGFloat) -> Path {
        var path = Path()
        switch self {
        case .leaf:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -53))
            path.move(to: CGPoint(x: 0, y: -14))
            path.addCurve(to: CGPoint(x: -34, y: -44), control1: CGPoint(x: -24, y: -15), control2: CGPoint(x: -34, y: -32))
            path.addCurve(to: CGPoint(x: 0, y: -14), control1: CGPoint(x: -12, y: -42), control2: CGPoint(x: -1, y: -31))
            path.move(to: CGPoint(x: 0, y: -30))
            path.addCurve(to: CGPoint(x: 27, y: -77), control1: CGPoint(x: 25, y: -39), control2: CGPoint(x: 30, y: -62))
            path.addCurve(to: CGPoint(x: 0, y: -30), control1: CGPoint(x: 7, y: -66), control2: CGPoint(x: -1, y: -47))
        case .circles:
            path.addEllipse(in: CGRect(x: -27, y: -65, width: 54, height: 54))
            path.addEllipse(in: CGRect(x: -36, y: -37, width: 40, height: 40))
        case .mountains:
            path.move(to: CGPoint(x: -48, y: 0))
            path.addLine(to: CGPoint(x: -17, y: -36))
            path.addLine(to: CGPoint(x: 14, y: 0))
            path.move(to: CGPoint(x: -10, y: -28))
            path.addLine(to: CGPoint(x: 14, y: -56))
            path.addLine(to: CGPoint(x: 50, y: -14))
        case .arch:
            // 큰 아치 — 왼쪽 기둥을 올라 위로 반원을 그리고 오른쪽 기둥으로 내려온다(화면 좌표에서 각이 커지는 쪽이 시계 방향이다).
            path.move(to: CGPoint(x: -30, y: 0))
            path.addLine(to: CGPoint(x: -30, y: -47))
            path.addArc(center: CGPoint(x: -5, y: -47), radius: 25, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            path.addLine(to: CGPoint(x: 20, y: 0))
            // 작은 아치.
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -26))
            path.addArc(center: CGPoint(x: 21, y: -26), radius: 21, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            path.addLine(to: CGPoint(x: 42, y: 0))
            path.addEllipse(in: CGRect(x: 23, y: -92, width: 20, height: 20))
        }
        return path.applying(CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale))
    }
}

/// 책장 표지(시안 P1 의 188 × 210 표지) — 표지 색 · 책등 · 「새기다」 · 번호와 「필사」 또는 큰 삽화 · 바닥 선.
///
/// 표지는 그림이라 글자 크기를 고정한다(글자 크기 설정과 상관없이 같은 표지). 이름 · 기록은 표지 아래에 따로 보인다.
struct NotebookCoverView: View {
    let style: NotebookCoverStyle

    @Environment(\.colorScheme) private var colorScheme

    static let size = CGSize(width: 188, height: 210)
    private static let cornerRadius: CGFloat = 5
    /// 책등 폭과 그 옆 밝은 선 자리(시안 x = 14).
    private static let spineWidth: CGFloat = 13

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            style.theme.coverColor
            style.theme.spineColor
                .frame(width: Self.spineWidth)
            Color.white.opacity(0.28)
                .frame(width: 1)
                .offset(x: Self.spineWidth + 0.5)
            artwork
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(shape)
        .shadow(color: shadowColor, radius: 2, x: 0, y: 2)
        .accessibilityHidden(true)
    }

    /// 표지 위 글자 · 삽화 · 바닥 선을 시안 좌표 그대로 그린다. 글자는 시안처럼 첫 기준선을 좌표에 맞춘다 —
    /// 뷰 배치의 기준선 정렬은 감싼 뷰 크기 · 조건문에 따라 어긋나서, 글자 크기를 재어 직접 그린다.
    private var artwork: some View {
        let color = style.theme.contentColor
        let illustration = style.theme.illustration
        let number = style.number
        // 번호가 있으면 삽화를 오른쪽 아래에 작게, 없으면 가운데에 크게(시안 translate(132 188) scale .65 · translate(102 183) scale 1.15).
        let origin = number == nil ? CGPoint(x: 102, y: 183) : CGPoint(x: 132, y: 188)
        let scale: CGFloat = number == nil ? 1.15 : 0.65
        let brand = Text("새기다", bundle: .module).font(.system(size: 9))
        let label = Text("필사", bundle: .module, comment: "책장 표지 번호 아래 글자 — 03 필사(2.2 필사책 표지)").font(.system(size: 10))
        return Canvas { context, _ in
            var illustrationContext = context
            illustrationContext.opacity = number == nil ? 0.7 : 0.75
            illustrationContext.stroke(
                illustration.path(origin: origin, scale: scale),
                with: .color(color),
                style: StrokeStyle(lineWidth: illustration.lineWidth * scale, lineCap: .round, lineJoin: .round)
            )
            var bottomLine = Path()
            bottomLine.move(to: CGPoint(x: 32, y: 190))
            bottomLine.addLine(to: CGPoint(x: 164, y: 190))
            context.stroke(bottomLine, with: .color(color.opacity(0.35)), lineWidth: 0.8)

            Self.draw(brand, color: color, opacity: 0.8, baselineAt: CGPoint(x: 32, y: 33), in: context)
            if let number {
                let numberText = Text(verbatim: NotebookCoverStyle.numberText(number)).font(.system(size: 48, weight: .thin))
                Self.draw(numberText, color: color, baselineAt: CGPoint(x: 30, y: 94), in: context)
                Self.draw(label, color: color, baselineAt: CGPoint(x: 33, y: 112), in: context)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// 역할: 글자의 첫 기준선을 표지 좌표 `point` 에 맞춰 그린다(시안의 text x · y 가 기준선이다).
    /// 입력 · 출력: 글자 · 색 · 불투명도 · 기준선 시작점 · 그릴 곳 → 없음.
    /// 부작용: `context` 에 그린다.
    private static func draw(_ text: Text, color: Color, opacity: Double = 1, baselineAt point: CGPoint, in context: GraphicsContext) {
        var context = context
        context.opacity = opacity
        var resolved = context.resolve(text)
        resolved.shading = .color(color)
        let measured = resolved.measure(in: size)
        let origin = CGPoint(x: point.x, y: point.y - resolved.firstBaseline(in: measured))
        context.draw(resolved, in: CGRect(origin: origin, size: measured))
    }

    /// 시안의 그림자(먹색 10%)는 다크 바탕에서 보이지 않아 다크에서는 검정으로 짙게 둔다.
    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.35) : Color(red: 0x30 / 255, green: 0x3B / 255, blue: 0x36 / 255).opacity(0.10)
    }
}
