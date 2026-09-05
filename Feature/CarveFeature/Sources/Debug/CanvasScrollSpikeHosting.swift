//
//  CanvasScrollSpikeHosting.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import Domain
import PencilKit
import SwiftUI
import UIKit

// MARK: - 공통 설정

enum SpikeCanvasSetup {
    /// A/B 공통 캔버스 설정.
    ///
    /// `zoomScale`을 1로 고정하는 것은 측정의 전제이기도 하다(`CanvasScrollSpikeMetrics` 주석 참조).
    /// 값이 흔들리면 HUD의 zoom 표시로 바로 드러난다.
    static func configure(_ canvas: PKCanvasView, allowFingerDrawing: Bool) {
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = allowFingerDrawing ? .anyInput : .pencilOnly
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.zoomScale = 1
        canvas.bouncesZoom = false
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
    }
}

/// 통과 기준 5(롱프레스 메뉴 / 탭 제스처)를 확인하기 위한 제스처 부착기.
///
/// `cancelsTouchesInView = false`로 두어 필기·스크롤을 가로채지 않는다.
final class SpikeGestureBinder: NSObject, UIGestureRecognizerDelegate {
    private weak var metrics: CanvasScrollSpikeMetrics?

    func bind(to view: UIView, metrics: CanvasScrollSpikeMetrics) {
        guard self.metrics == nil else { return }
        self.metrics = metrics
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        for recognizer in [tap, longPress] as [UIGestureRecognizer] {
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
        }
    }

    @objc private func handleTap() {
        MainActor.assumeIsolated { metrics?.countTap() }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        MainActor.assumeIsolated { metrics?.countLongPress() }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
}

// MARK: - A: SwiftUI ScrollView + content-sized overlay

/// A 모드의 캔버스. 스크롤은 상위 SwiftUI `ScrollView`가 담당하므로 자신은 스크롤하지 않는다.
final class SpikeOverlayCanvasView: PKCanvasView {
    /// 설계 §11이 말하는 "StableCanvasView 수준의 정규화"를 매 레이아웃마다 적용할지 여부.
    /// **끄면 drift가 그대로 보인다.** 켜고 끈 결과를 비교하는 것이 A 평가의 핵심이다.
    var normalizeScrollState = false
    var onAttach: ((SpikeOverlayCanvasView, UIScrollView?) -> Void)?
    private var didReportAttach = false

    override func layoutSubviews() {
        super.layoutSubviews()
        // overlay는 content 전체 크기로 배치되므로 캔버스 자신의 content는 bounds와 같아야 한다.
        if contentSize != bounds.size, bounds.width > 0, bounds.height > 0 {
            contentSize = bounds.size
        }
        if normalizeScrollState { normalizeNow() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !didReportAttach else { return }
        didReportAttach = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.onAttach?(self, self.enclosingScrollView())
        }
    }

    /// 상위 SwiftUI `ScrollView`가 실제로 쓰는 `UIScrollView`를 찾는다.
    /// 하네스가 프로그램 스크롤을 걸고 HUD에 offset을 찍기 위한 유일한 경로다(Debug 전용).
    private func enclosingScrollView() -> UIScrollView? {
        var candidate = superview
        while let current = candidate {
            if let scrollView = current as? UIScrollView { return scrollView }
            candidate = current.superview
        }
        return nil
    }

    private func normalizeNow() {
        UIView.performWithoutAnimation {
            if contentInset != .zero { contentInset = .zero }
            if contentOffset != .zero { contentOffset = .zero }
            if zoomScale != 1 { zoomScale = 1 }
        }
    }
}

struct SpikeOverlayCanvas: UIViewRepresentable {
    let drawing: PKDrawing
    let contentKey: String
    let allowFingerDrawing: Bool
    let normalize: Bool
    let metrics: CanvasScrollSpikeMetrics
    let onAttach: () -> Void

    func makeUIView(context: Context) -> SpikeOverlayCanvasView {
        let canvas = SpikeOverlayCanvasView()
        SpikeCanvasSetup.configure(canvas, allowFingerDrawing: allowFingerDrawing)
        canvas.isScrollEnabled = false
        canvas.bounces = false
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        canvas.drawing = drawing
        canvas.normalizeScrollState = normalize
        context.coordinator.appliedKey = contentKey
        context.coordinator.binder.bind(to: canvas, metrics: metrics)
        let metrics = self.metrics
        let onAttach = self.onAttach
        canvas.onAttach = { canvasView, scrollView in
            MainActor.assumeIsolated {
                metrics.attach(canvas: canvasView, governing: scrollView, columnOrigin: .zero)
                metrics.resetReference(note: "A 모드 attach")
                onAttach()
            }
        }
        return canvas
    }

    func updateUIView(_ canvas: SpikeOverlayCanvasView, context: Context) {
        canvas.normalizeScrollState = normalize
        canvas.drawingPolicy = allowFingerDrawing ? .anyInput : .pencilOnly
        guard context.coordinator.appliedKey != contentKey else { return }
        context.coordinator.appliedKey = contentKey
        canvas.drawing = drawing
        // `updateUIView`는 SwiftUI 업데이트 사이클 안이라 여기서 @Published를 건드리면 경고가 난다.
        let metrics = self.metrics
        DispatchQueue.main.async { metrics.resetReference(note: "A 모드 콘텐츠 갱신") }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var appliedKey: String = ""
        let binder = SpikeGestureBinder()
    }
}

// MARK: - B: PKCanvasView 단독 scroll + 내부 UIHostingController

/// B 모드의 캔버스. **이 앱에서 유일한 `UIScrollView`다.**
/// 텍스트 호스팅 뷰를 자신의 scroll content 안에 두고 z-order를 잉크 아래로 유지한다.
final class SpikeSingleScrollCanvas: PKCanvasView {
    weak var contentHostView: UIView?
    var contentFrame: CGRect = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let host = contentHostView else { return }
        if host.frame != contentFrame { host.frame = contentFrame }
        // PencilKit이 내부 뷰를 다시 붙여도 텍스트가 잉크를 덮지 않도록 매번 뒤로 보낸다.
        if subviews.first !== host { sendSubviewToBack(host) }
    }
}

/// B 모드 컨테이너.
///
/// 설계 §11의 **금지 사항**(캔버스와 별개인 SwiftUI 텍스트에 `contentOffset`만 전달)을 피하기 위해
/// 텍스트는 `canvas.insertSubview(_:at: 0)`으로 **scroll content 내부**에 들어간다.
/// 그래서 스크롤 동기화 코드가 아예 존재하지 않는다 — 텍스트는 잉크와 같은 content 좌표계를 공유한다.
final class SpikeSingleScrollController: UIViewController {
    let canvas = SpikeSingleScrollCanvas()
    var metrics: CanvasScrollSpikeMetrics?
    var onAttach: (() -> Void)?

    private var textHost: UIHostingController<SpikeVerseColumn>?
    private let binder = SpikeGestureBinder()
    private var layout: ChapterLayout?
    private var baseDrawing = PKDrawing()
    private var contentKey = ""
    private var isLeftHanded = false
    private var appliedColumnX: CGFloat = .nan
    private var didAttach = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.isScrollEnabled = true
        canvas.alwaysBounceVertical = true
        canvas.showsVerticalScrollIndicator = true
        view.addSubview(canvas)
    }

    /// 레이아웃·Drawing·모드 옵션을 반영한다.
    func apply(
        layout: ChapterLayout,
        drawing: PKDrawing,
        contentKey: String,
        probeVerses: Set<Int>,
        isLeftHanded: Bool,
        allowFingerDrawing: Bool,
        metrics: CanvasScrollSpikeMetrics
    ) {
        self.metrics = metrics
        SpikeCanvasSetup.configure(canvas, allowFingerDrawing: allowFingerDrawing)
        binder.bind(to: canvas, metrics: metrics)

        let column = SpikeVerseColumn(layout: layout, probeVerses: probeVerses, metrics: metrics)
        if let textHost {
            textHost.rootView = column
        } else {
            let host = UIHostingController(rootView: column)
            host.view.backgroundColor = .clear
            // 텍스트는 표시만 한다. 터치는 전부 캔버스(스크롤/필기)로 간다.
            host.view.isUserInteractionEnabled = false
            addChild(host)
            canvas.insertSubview(host.view, at: 0)
            host.didMove(toParent: self)
            canvas.contentHostView = host.view
            textHost = host
        }

        let changed = contentKey != self.contentKey || isLeftHanded != self.isLeftHanded
        self.layout = layout
        self.baseDrawing = drawing
        self.contentKey = contentKey
        self.isLeftHanded = isLeftHanded
        if changed { appliedColumnX = .nan }
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let layout, view.bounds.width > 0 else { return }
        let columnX = isLeftHanded ? 0 : max(0, view.bounds.width - layout.writingWidth)
        canvas.contentFrame = CGRect(x: columnX, y: 0, width: layout.writingWidth, height: layout.totalHeight)
        canvas.contentSize = CGSize(width: view.bounds.width, height: layout.totalHeight)
        canvas.setNeedsLayout()

        guard appliedColumnX != columnX else { return }
        appliedColumnX = columnX
        // layout 좌표 → 캔버스 content 좌표. 잉크와 텍스트가 같은 평행이동을 받는다.
        canvas.drawing = baseDrawing.transformed(using: CGAffineTransform(translationX: columnX, y: 0))
        metrics?.attach(canvas: canvas, governing: canvas, columnOrigin: CGPoint(x: columnX, y: 0))
        // 레이아웃 패스는 SwiftUI 업데이트 사이클 안일 수 있어 @Published 변경은 다음 런루프로 미룬다.
        let shouldReportAttach = !didAttach
        didAttach = true
        DispatchQueue.main.async { [weak self] in
            self?.metrics?.resetReference(note: "B 모드 attach (columnX=\(Int(columnX)))")
            if shouldReportAttach { self?.onAttach?() }
        }
    }
}

struct CanvasScrollSpikeModeB: UIViewControllerRepresentable {
    let layout: ChapterLayout
    let drawing: PKDrawing
    let contentKey: String
    let probeVerses: Set<Int>
    let metrics: CanvasScrollSpikeMetrics
    let isLeftHanded: Bool
    let allowFingerDrawing: Bool
    let onAttach: () -> Void

    func makeUIViewController(context: Context) -> SpikeSingleScrollController {
        let controller = SpikeSingleScrollController()
        controller.onAttach = onAttach
        applyState(to: controller)
        return controller
    }

    func updateUIViewController(_ controller: SpikeSingleScrollController, context: Context) {
        applyState(to: controller)
    }

    private func applyState(to controller: SpikeSingleScrollController) {
        controller.apply(
            layout: layout,
            drawing: drawing,
            contentKey: contentKey,
            probeVerses: probeVerses,
            isLeftHanded: isLeftHanded,
            allowFingerDrawing: allowFingerDrawing,
            metrics: metrics
        )
    }
}
#endif
