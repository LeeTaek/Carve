//
//  ChapterCanvasController.swift
//  CarveFeature
//
//  Created by Claude on 9/6/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import CarveToolkit
import Domain
import PencilKit
import SwiftUI
import UIKit

/// B 구조의 캔버스 (설계 §11 · §12 U4). **이 화면에서 유일한 `UIScrollView`** 다.
///
/// 텍스트 컬럼(`UIHostingController`)을 자신의 scroll content 안, 잉크 **아래**에 둔다. 스크롤 동기화 코드는 없다 —
/// 텍스트와 잉크가 같은 content 좌표계를 공유한다 (S4 하네스의 `SpikeSingleScrollCanvas` 와 같은 원칙).
final class ChapterPKCanvasView: PKCanvasView {
    weak var contentHostView: UIView?
    var contentFrame: CGRect = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let host = contentHostView else { return }
        if host.frame != contentFrame { host.frame = contentFrame }
        // PencilKit 이 내부 뷰를 다시 붙여도 텍스트가 잉크를 덮지 않도록 매번 뒤로 보낸다.
        if subviews.first !== host { sendSubviewToBack(host) }
    }
}

/// 단일 Canvas 호스팅 컨트롤러 — PencilKit 타입은 여기(와 `ChapterCanvasView`)까지만 온다 (설계 §4).
///
/// 하는 일은 셋이다.
/// 1. **표시:** `renderedRevision` 이 바뀔 때만 `Data` 를 디코드해 `drawing` 에 넣고 undo 스택을 비운다 (§4 · §9-5).
/// 2. **편집 계약:** 도구 시작 → `editBegan`, drawing 변경 → trailing debounce 뒤 `editEnded`, 변경 없이 도구 종료 → `editCancelled` (§8-1).
///    `canvasViewDidEndUsingTool` 을 저장 지점으로 쓰지 않는다 — PencilKit 이 획을 반영하기 전에 호출된다 (§7-5 실측).
/// 3. **기하:** 텍스트 컬럼 높이 = content 높이, 헤더는 `contentInset.top` 으로 비운다 (콘텐츠 좌표는 헤더와 무관).
///    하단은 safe area 만큼 inset 을 더해 마지막 절이 홈 인디케이터에 가리지 않게 한다 (§5 미결 → `.never` + inset 채택).
final class ChapterCanvasController: UIViewController, PKCanvasViewDelegate {

    /// 컨트롤러가 밖으로 알리는 사건. Coordinator 가 Feature 액션으로 옮긴다.
    enum Event {
        case editBegan
        case editEnded(CanvasEditSnapshot)
        case editCancelled
        case undoStateChanged(canUndo: Bool, canRedo: Bool)
        /// SwiftUI `offsetY` 와 같은 의미의 (이전, 현재) 콘텐츠 상단 y. 맨 위에서 0, 내려가면 음수.
        case scrolled(previous: CGFloat, current: CGFloat)
    }

    /// 뷰가 매 업데이트마다 넘기는 표시 상태.
    struct Configuration {
        var renderedData: Data?
        var renderedRevision: Int
        var isInputEnabled: Bool
        var tool: PKTool
        var drawingPolicy: PKCanvasViewDrawingPolicy
        var topInset: CGFloat
        var undoRequestVersion: Int
        var redoRequestVersion: Int
        var scrollRequest: ChapterCanvasFeature.State.ScrollRequest?
        /// 스크롤 요청을 content y 로 바꿔 줄 레이아웃 (없으면 요청을 보류).
        var layout: ChapterLayout?
    }

    var onEvent: (@MainActor (Event) -> Void)?

    let canvas = ChapterPKCanvasView()
    private let host = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))

    private var appliedRevision = -1
    private var appliedUndoVersion = 0
    private var appliedRedoVersion = 0
    private var appliedScrollToken = 0
    private var appliedTopInset: CGFloat = -1
    private var columnHeight: CGFloat = 0
    private var isApplyingDrawing = false
    private var isPerformingHistory: EditReason?
    private var didChangeSinceToolBegan = false
    private var trailingEditTask: Task<Void, Never>?
    private var cancelCheckTask: Task<Void, Never>?
    private var lastReportedTop: CGFloat = 0
    private var lastBounds: CGRect = .zero

    /// pencil-up 판정용 trailing debounce (CanvasView 와 같은 값).
    private let editSettleInterval: TimeInterval = 0.3

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = self
        canvas.isScrollEnabled = true
        canvas.alwaysBounceVertical = true
        canvas.showsVerticalScrollIndicator = true
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.zoomScale = 1
        canvas.bouncesZoom = false
        canvas.pinchGestureRecognizer?.isEnabled = false
        // 자동 인셋 조정은 offset drift 의 원인 중 하나다 (§5 · §11). 인셋은 아래에서 명시적으로 준다.
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.drawingGestureRecognizer.isEnabled = false
        view.addSubview(canvas)

        host.view.backgroundColor = .clear
        // 텍스트는 표시만 한다. 터치는 전부 캔버스(스크롤/필기)로 간다.
        host.view.isUserInteractionEnabled = false
        addChild(host)
        canvas.insertSubview(host.view, at: 0)
        host.didMove(toParent: self)
        canvas.contentHostView = host.view
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.bounds != lastBounds {
            lastBounds = view.bounds
            updateContentGeometry()
        }
    }

    // MARK: 밖에서 들어오는 갱신

    /// 텍스트 컬럼을 교체한다. 높이는 컬럼이 스스로 보고한다 (`setColumnHeight`).
    func setColumn(_ column: AnyView) {
        host.rootView = column
    }

    /// 컬럼이 `onGeometryChange` 로 보고한 자기 높이.
    func setColumnHeight(_ height: CGFloat) {
        guard height != columnHeight else { return }
        columnHeight = height
        updateContentGeometry()
    }

    func apply(_ configuration: Configuration) {
        canvas.drawingGestureRecognizer.isEnabled = configuration.isInputEnabled
        canvas.tool = configuration.tool
        canvas.drawingPolicy = configuration.drawingPolicy

        if configuration.topInset != appliedTopInset {
            let isFirst = appliedTopInset < 0
            appliedTopInset = configuration.topInset
            updateContentGeometry()
            if isFirst { canvas.setContentOffset(CGPoint(x: 0, y: -configuration.topInset), animated: false) }
        }

        if configuration.renderedRevision != appliedRevision {
            appliedRevision = configuration.renderedRevision
            applyDrawing(configuration.renderedData)
        }

        if configuration.undoRequestVersion != appliedUndoVersion {
            appliedUndoVersion = configuration.undoRequestVersion
            performHistory(.undo)
        }
        if configuration.redoRequestVersion != appliedRedoVersion {
            appliedRedoVersion = configuration.redoRequestVersion
            performHistory(.redo)
        }

        if let request = configuration.scrollRequest, request.token != appliedScrollToken, let layout = configuration.layout {
            appliedScrollToken = request.token
            scroll(toVerse: request.verse, layout: layout)
        }
    }

    // MARK: 표시

    private func applyDrawing(_ data: Data?) {
        let drawing: PKDrawing
        if let data, !data.isEmpty, let decoded = try? PKDrawing(data: data) {
            drawing = decoded
        } else {
            drawing = PKDrawing()
        }
        isApplyingDrawing = true
        canvas.drawing = drawing
        isApplyingDrawing = false
        // 합성·복원·reflow 뒤에는 이전 undo 스택이 의미를 잃는다 (§9-5).
        canvas.undoManager?.removeAllActions()
        trailingEditTask?.cancel()
        cancelCheckTask?.cancel()
        didChangeSinceToolBegan = false
        reportUndoState()
    }

    private func updateContentGeometry() {
        let width = view.bounds.width
        guard width > 0 else { return }
        let inset = max(0, appliedTopInset)
        let height = max(columnHeight, view.bounds.height - inset)
        canvas.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: view.safeAreaInsets.bottom + 24, right: 0)
        canvas.contentFrame = CGRect(x: 0, y: 0, width: width, height: height)
        canvas.contentSize = CGSize(width: width, height: height)
        canvas.setNeedsLayout()
    }

    private func scroll(toVerse verse: Int, layout: ChapterLayout) {
        guard let region = layout.region(verse: verse) else { return }
        // 이전(N-Canvas) 동작과 같이 해당 절이 화면 하단 근처에 오도록 한다.
        let visibleHeight = canvas.bounds.height - canvas.contentInset.top - canvas.contentInset.bottom
        let target = region.writingRect.maxY - visibleHeight + 40
        let minOffset = -canvas.contentInset.top
        let maxOffset = max(minOffset, canvas.contentSize.height - canvas.bounds.height + canvas.contentInset.bottom)
        let offsetY = min(max(target, minOffset), maxOffset)
        canvas.setContentOffset(CGPoint(x: 0, y: offsetY), animated: true)
    }

    // MARK: undo / redo

    private func performHistory(_ reason: EditReason) {
        guard let undoManager = canvas.undoManager else { return }
        isPerformingHistory = reason
        defer { isPerformingHistory = nil }
        switch reason {
        case .undo where undoManager.canUndo: undoManager.undo()
        case .redo where undoManager.canRedo: undoManager.redo()
        default: break
        }
    }

    private func reportUndoState() {
        onEvent?(.undoStateChanged(
            canUndo: canvas.undoManager?.canUndo ?? false,
            canRedo: canvas.undoManager?.canRedo ?? false
        ))
    }

    // MARK: PKCanvasViewDelegate — 편집 계약 (§8-1)

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        cancelCheckTask?.cancel()
        didChangeSinceToolBegan = false
        onEvent?(.editBegan)
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        // 변경 없이 끝난 도구 사용(탭 등)은 editEnded 가 오지 않으므로, 잠시 뒤에도 변경이 없으면 취소로 알린다.
        cancelCheckTask?.cancel()
        cancelCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.35))
            guard let self, !Task.isCancelled, !self.didChangeSinceToolBegan else { return }
            self.onEvent?(.editCancelled)
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing else { return }
        didChangeSinceToolBegan = true
        cancelCheckTask?.cancel()
        let reason: EditReason
        if let history = isPerformingHistory {
            reason = history
        } else {
            reason = canvasView.tool is PKEraserTool ? .erase : .ink
        }
        // 제스처의 마지막 변경까지 반드시 포함시키기 위한 trailing debounce (§7-5).
        trailingEditTask?.cancel()
        trailingEditTask = Task { @MainActor [weak self, weak canvasView] in
            try? await Task.sleep(for: .seconds(self?.editSettleInterval ?? 0.3))
            guard let self, let canvasView, !Task.isCancelled else { return }
            let drawing = canvasView.drawing
            let bounds = drawing.bounds
            self.onEvent?(.editEnded(CanvasEditSnapshot(
                drawingData: drawing.dataRepresentation(),
                dirtyBounds: (bounds.isNull || bounds.isEmpty) ? nil : bounds,
                reason: reason
            )))
            self.reportUndoState()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // SwiftUI 경로의 offsetY 와 같은 값: 콘텐츠 상단이 뷰포트 상단에 있으면 0, 내려가면 음수.
        let current = -(scrollView.contentOffset.y + scrollView.contentInset.top)
        guard current != lastReportedTop else { return }
        let previous = lastReportedTop
        lastReportedTop = current
        onEvent?(.scrolled(previous: previous, current: current))
    }
}
