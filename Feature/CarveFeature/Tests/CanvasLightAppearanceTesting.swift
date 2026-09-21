//
//  CanvasLightAppearanceTesting.swift
//  CarveFeatureTest
//
//  결정 8-1 안 1 — 다크에서도 필사 캔버스는 라이트로 그려 저장된 잉크 색을 그대로 보인다.
//

import Domain
import Foundation
import PencilKit
import SwiftUI
import Testing
import UIKit

import ComposableArchitecture

@testable import CarveFeature

/// 캔버스를 담은 SwiftUI 표현 뷰를 다크 화면에 띄워, 캔버스의 외관과 실제로 그려진 잉크 색을 본다.
///
/// 장 화면(`CarveDetailView`)은 띄우지 않는다. 장을 열면 공유 인메모리 저장소(`drawingData`)를 읽어,
/// 누가 먼저 저장소를 깨우는지에 민감한 `DrawingErasePersistenceTesting` 이 순서에 따라 실패한다(2026-09-15 전체 회귀).
@Suite("다크 모드 — 필사 캔버스 라이트 고정 (결정 8-1 안 1)")
@MainActor
struct CanvasLightAppearanceTesting {

    /// 화면이 다크가 되는 두 경로.
    enum DarkSource: String, CaseIterable, Sendable {
        /// 기기 설정이 다크 — 창의 외관이 다크다.
        case system
        /// 설정 › 화면 모드 「다크」 — 루트 화면의 `preferredColorScheme(.dark)`.
        case appSetting
    }

    private struct Pixel: CustomStringConvertible {
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Int
        var description: String { "rgba(\(red),\(green),\(blue),\(alpha))" }
    }

    /// 검정 펜 한 획.
    nonisolated private static func blackInkData() -> Data {
        let points = (0..<30).map { index in
            PKStrokePoint(
                location: CGPoint(x: 10 + CGFloat(index) * 4, y: 8),
                timeOffset: TimeInterval(index) * 0.01,
                size: CGSize(width: 12, height: 12),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_000))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)]).dataRepresentation()
    }

    private func host(_ root: some View, source: DarkSource) -> (UIWindow, UIViewController) {
        let hosting = UIHostingController(rootView: root.preferredColorScheme(source == .appSetting ? .dark : nil))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1_200))
        window.overrideUserInterfaceStyle = source == .system ? .dark : .light
        window.rootViewController = hosting
        window.isHidden = false
        return (window, hosting)
    }

    private func findController(_ root: UIViewController?) -> ChapterCanvasController? {
        guard let root else { return nil }
        if let match = root as? ChapterCanvasController { return match }
        for child in root.children {
            if let match = findController(child) { return match }
        }
        return nil
    }

    private func canvases(in view: UIView) -> [PKCanvasView] {
        if let canvas = view as? PKCanvasView { return [canvas] }
        return view.subviews.flatMap { canvases(in: $0) }
    }

    /// SwiftUI 갱신과 PencilKit 렌더가 도는 시간을 준다.
    private func pump(_ window: UIWindow, turns: Int = 60) async {
        for _ in 0..<turns {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// 레이어를 그린 이미지. PencilKit 이 그린 잉크는 레이어 내용에 담긴다 — `drawHierarchy` 는 테스트 창에서 비어 나왔다.
    private func renderLayer(_ view: UIView) -> UIImage {
        UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    /// 가장 불투명한 픽셀. 잉크만 있는 캔버스에서 잉크 색을 읽는다. 다 투명하면 nil.
    private func mostOpaquePixel(_ image: UIImage) -> Pixel? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let isDrawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard isDrawn else { return nil }
        var best: Pixel?
        for index in stride(from: 0, to: bytes.count, by: 4) where Int(bytes[index + 3]) > (best?.alpha ?? 0) {
            best = Pixel(red: Int(bytes[index]), green: Int(bytes[index + 1]), blue: Int(bytes[index + 2]), alpha: Int(bytes[index + 3]))
        }
        return best
    }

    /// ⚠️ `ChapterCanvasController` 가 컨트롤러에만 라이트를 걸던 때는 두 경로 모두 캔버스가 다크였고, 검정 잉크가 rgba(255,255,255,255) 로
    /// 그려졌다(2026-09-15). SwiftUI 에 담긴 컨트롤러의 외관 고정은 환경에 덮이므로 캔버스 뷰에 직접 건다.
    @Test("다크 화면에서도 단일 캔버스는 라이트이고 검정 잉크를 검정으로 그린다", arguments: DarkSource.allCases)
    func singleCanvasDrawsStoredInkColorInDark(source: DarkSource) async throws {
        var state = ChapterCanvasFeature.State(chapter: BibleChapter(title: .genesis, chapter: 1))
        state.renderedData = Self.blackInkData()
        state.renderedRevision = 1
        let store = Store(initialState: state) { ChapterCanvasFeature() }
        let canvasView = ChapterCanvasView(
            store: store,
            display: ChapterCanvasView.Display(state),
            topInset: 0,
            bottomInset: 0,
            column: AnyView(Color.clear.frame(height: 400)),
            onScroll: { _, _ in }
        )
        let (window, hosting) = host(canvasView, source: source)
        defer { window.isHidden = true }
        await pump(window)

        let controller = try #require(findController(hosting), "컨트롤러를 찾지 못했다")
        // 전제: 화면은 실제로 다크다. 아니면 이 테스트는 아무것도 확인하지 않는다.
        #expect(hosting.traitCollection.userInterfaceStyle == .dark)
        #expect(controller.canvas.traitCollection.userInterfaceStyle == .light)

        try #require(!controller.canvas.drawing.bounds.isEmpty, "캔버스에 잉크가 들어가지 않았다")
        let ink = try #require(mostOpaquePixel(renderLayer(controller.canvas)), "캔버스에 그려진 잉크가 없다")
        #expect(ink.red < 64 && ink.green < 64 && ink.blue < 64, "검정 잉크가 \(ink) 로 그려졌다")
    }

    @Test("다크 화면에서도 절 캔버스(N-Canvas)는 라이트이고 검정 잉크를 검정으로 그린다", arguments: DarkSource.allCases)
    func verseCanvasDrawsStoredInkColorInDark(source: DarkSource) async throws {
        try await withDependencies {
            $0.undoManager = SharedUndoManager()
        } operation: {
            let chapter = BibleChapter(title: .genesis, chapter: 1)
            let drawing = BibleDrawing(bibleTitle: chapter, verse: 1, lineData: Self.blackInkData())
            let store = Store(
                initialState: CanvasFeature.State(sentence: BibleVerse(title: chapter, verse: 1, sentence: "태초에"), drawing: drawing)
            ) {
                CanvasFeature()
            }
            let (window, hosting) = host(CanvasView(store: store).frame(width: 400, height: 200), source: source)
            defer { window.isHidden = true }
            await pump(window)

            #expect(hosting.traitCollection.userInterfaceStyle == .dark)
            let canvas = try #require(canvases(in: hosting.view).first, "절 캔버스를 찾지 못했다")
            #expect(canvas.traitCollection.userInterfaceStyle == .light)
            let ink = try #require(mostOpaquePixel(renderLayer(canvas)), "캔버스에 그려진 잉크가 없다")
            #expect(ink.red < 64 && ink.green < 64 && ink.blue < 64, "검정 잉크가 \(ink) 로 그려졌다")
        }
    }
}
