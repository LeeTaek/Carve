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
///    교체 직전에 아직 보고하지 않은 편집이 있으면 **이전 세대 번호로** 먼저 보고한다 — 장 전환 직전의 마지막 획.
/// 2. **편집 계약:** 도구 시작 → `editBegan`, drawing 변경 → trailing debounce 뒤 `editEnded(세대)`, 변경 없이 도구 종료 → `editCancelled` (§8-1).
///    `canvasViewDidEndUsingTool` 을 저장 지점으로 쓰지 않는다 — PencilKit 이 획을 반영하기 전에 호출된다 (§7-5 실측).
///    새 획이 시작되면 직전 획의 trailing 보고를 **취소**한다. 획 도중 `editEnded` 가 나가면 `isEditing` 이 풀려 보류된 레이아웃이
///    획 중간에 적용된다. 미보고 변경은 다음 도구 종료 뒤에 함께 보고한다.
/// 3. **기하:** 텍스트 컬럼 높이 = 컬럼 자신의 높이(content 높이가 아니다), 헤더는 `contentInset.top` 으로 비운다 (콘텐츠 좌표는 헤더와 무관).
///    하단은 safe area 만큼 inset 을 더해 마지막 절이 홈 인디케이터에 가리지 않게 한다 (§5 미결 → `.never` + inset 채택).
/// 4. **히스토리 메뉴:** 텍스트 호스트는 터치를 받지 않으므로(`isUserInteractionEnabled = false`) 행별 컨텍스트 메뉴가 닿지 않는다.
///    대신 캔버스 한 곳의 손가락 롱프레스 → `UIEditMenuInteraction` 메뉴 → `historyRequested(at:)` 로 알리고,
///    절 판정은 Feature 가 `ChapterLayout.verse(containing:)` 로 한다 (§8-7 rev.16 부록 — (3/3)).
final class ChapterCanvasController: UIViewController, PKCanvasViewDelegate, UIEditMenuInteractionDelegate {

    /// 컨트롤러가 밖으로 알리는 사건. Coordinator 가 Feature 액션으로 옮긴다.
    enum Event {
        case editBegan
        case editEnded(CanvasEditSnapshot)
        case editCancelled
        case undoStateChanged(canUndo: Bool, canRedo: Bool)
        /// SwiftUI `offsetY` 와 같은 의미의 (이전, 현재) 콘텐츠 상단 y. 맨 위에서 0, 내려가면 음수.
        case scrolled(previous: CGFloat, current: CGFloat)
        /// 롱프레스 메뉴에서 "이전 필사 내용 보기" 를 골랐다. 좌표는 캔버스 content 좌표.
        case historyRequested(at: CGPoint)
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

    /// 캔버스가 지금 표시하는 내용의 세대 (`renderedRevision`). `editEnded` 에 실어 보낸다.
    private(set) var appliedRevision = -1
    private var appliedUndoVersion = 0
    private var appliedRedoVersion = 0
    private var appliedScrollToken = 0
    private var appliedTopInset: CGFloat = -1
    private var columnHeight: CGFloat = 0
    private var isApplyingDrawing = false
    private var isPerformingHistory: EditReason?
    /// drawing 이 바뀌었는데 아직 `editEnded` 로 보고하지 않았다.
    private(set) var hasUnreportedChange = false
    private var unreportedReason: EditReason = .ink
    private var trailingEditTask: Task<Void, Never>?
    private var cancelCheckTask: Task<Void, Never>?
    private var lastReportedTop: CGFloat = 0
    private var lastBounds: CGRect = .zero
    /// 롱프레스 메뉴. 메뉴 항목이 눌리면 `historyMenuPoint` 를 실어 보낸다.
    private var historyMenuInteraction: UIEditMenuInteraction?
    private let historyLongPress = UILongPressGestureRecognizer()
    private var historyMenuPoint: CGPoint?

    /// pencil-up 판정용 trailing debounce (CanvasView 와 같은 값).
    private let editSettleInterval: TimeInterval = 0.3
    /// 변경 없이 도구 사용이 끝났다고 보는 대기 시간. trailing 보고보다 길어야 한다.
    private let cancelCheckInterval: TimeInterval = 0.35

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

        // 히스토리 메뉴 — 손가락 롱프레스만 받는다. 펜슬은 필기용이라 제외 (N-Canvas 의 `touchIgnoringContextMenu(ignoringType: .pencil)` 과 같은 규칙).
        let interaction = UIEditMenuInteraction(delegate: self)
        canvas.addInteraction(interaction)
        historyMenuInteraction = interaction
        historyLongPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        historyLongPress.addTarget(self, action: #selector(handleHistoryLongPress(_:)))
        canvas.addGestureRecognizer(historyLongPress)
    }

    // MARK: 히스토리 메뉴 (§8-7)

    @objc private func handleHistoryLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let interaction = historyMenuInteraction else { return }
        // 스크롤 뷰의 좌표 = content 좌표. 메뉴도 같은 좌표계로 띄운다.
        let point = recognizer.location(in: canvas)
        historyMenuPoint = point
        interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        UIMenu(children: [
            UIAction(title: "이전 필사 내용 보기") { [weak self] _ in
                guard let self, let point = self.historyMenuPoint else { return }
                self.onEvent?(.historyRequested(at: point))
            }
        ])
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
            // 헤더 높이는 첫 apply 뒤에 실측돼 온다 (0 → 실제 높이). 맨 위에 있던 스크롤은 새 인셋만큼 다시 내려
            // 콘텐츠 상단이 헤더에 가리지 않게 한다. 이미 내려가 있으면 건드리지 않는다.
            let previousInset = max(0, appliedTopInset)
            let wasAtTop = canvas.contentOffset.y <= -previousInset + 0.5
            appliedTopInset = configuration.topInset
            updateContentGeometry()
            if wasAtTop { canvas.setContentOffset(CGPoint(x: 0, y: -configuration.topInset), animated: false) }
        }

        if configuration.renderedRevision != appliedRevision {
            let previousRevision = appliedRevision
            appliedRevision = configuration.renderedRevision
            applyDrawing(configuration.renderedData, replacingGeneration: previousRevision)
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

    private func applyDrawing(_ data: Data?, replacingGeneration previousGeneration: Int) {
        // 내용을 바꾸기 전에, 아직 보고하지 않은 편집을 이전 세대 번호로 보고한다 (장 전환 직전의 마지막 획, §8-5).
        flushUnreportedEdit(generation: previousGeneration)

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
        cancelCheckTask?.cancel()
        reportUndoState()
    }

    /// 미보고 변경을 지금 캔버스 내용으로 보고한다. 이벤트는 다음 턴에 보낸다 — 뷰 갱신(`updateUIViewController`) 도중에
    /// 액션을 보내지 않기 위함이며, 세대 번호를 들고 가므로 늦게 도착해도 Feature 가 자기 세대의 문맥으로 계산한다.
    private func flushUnreportedEdit(generation: Int) {
        trailingEditTask?.cancel()
        guard hasUnreportedChange else { return }
        hasUnreportedChange = false
        let snapshot = makeSnapshot(generation: generation)
        Task { @MainActor [weak self] in
            self?.onEvent?(.editEnded(snapshot))
        }
    }

    private func makeSnapshot(generation: Int) -> CanvasEditSnapshot {
        let drawing = canvas.drawing
        let bounds = drawing.bounds
        return CanvasEditSnapshot(
            drawingData: drawing.dataRepresentation(),
            dirtyBounds: (bounds.isNull || bounds.isEmpty) ? nil : bounds,
            reason: unreportedReason,
            generation: generation
        )
    }

    private func updateContentGeometry() {
        let width = view.bounds.width
        guard width > 0 else { return }
        let inset = max(0, appliedTopInset)
        let height = max(columnHeight, view.bounds.height - inset)
        canvas.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: view.safeAreaInsets.bottom + 24, right: 0)
        // 텍스트 호스트의 frame 은 **컬럼 자신의 높이**다. content 높이(뷰포트 이상)로 늘리면 UIHostingController 가 내용을
        // 세로 중앙에 놓아, 짧은 장에서 텍스트가 레이아웃 좌표(컬럼 상단 = content 상단)보다 아래로 내려가 잉크·소유권과 어긋난다.
        canvas.contentFrame = CGRect(x: 0, y: 0, width: width, height: columnHeight > 0 ? columnHeight : height)
        canvas.contentSize = CGSize(width: width, height: height)
        canvas.setNeedsLayout()
    }

    private func scroll(toVerse verse: Int, layout: ChapterLayout) {
        guard let region = layout.region(verse: verse) else { return }
        let offsetY = Self.scrollOffset(
            bringingBottomOf: region.writingRect,
            viewportHeight: canvas.bounds.height,
            contentInset: canvas.contentInset,
            contentHeight: canvas.contentSize.height
        )
        canvas.setContentOffset(CGPoint(x: 0, y: offsetY), animated: true)
    }

    /// 절이 화면 하단 근처에 오도록 하는 `contentOffset.y` (N-Canvas 의 `scrollTo(anchor: .bottom)` 과 같은 의미).
    ///
    /// 뷰포트 `[offset, offset + height]` 에서 헤더(`contentInset.top`)는 위쪽을, 하단 inset 은 아래쪽을 가리므로
    /// **보이는 하단 = offset + height − inset.bottom** 이다. top inset 은 여기에 관여하지 않는다.
    /// - Parameters:
    ///   - rect: 대상 절의 `writingRect` (content 좌표).
    ///   - viewportHeight: 캔버스 `bounds.height`.
    ///   - contentInset: 캔버스 인셋.
    ///   - contentHeight: `contentSize.height`.
    ///   - bottomMargin: 절 하단과 보이는 하단 사이 여백.
    /// - Returns: 범위 안으로 클램프된 offset y.
    static func scrollOffset(
        bringingBottomOf rect: CGRect,
        viewportHeight: CGFloat,
        contentInset: UIEdgeInsets,
        contentHeight: CGFloat,
        bottomMargin: CGFloat = 40
    ) -> CGFloat {
        let target = rect.maxY + bottomMargin - (viewportHeight - contentInset.bottom)
        let minOffset = -contentInset.top
        let maxOffset = max(minOffset, contentHeight - viewportHeight + contentInset.bottom)
        return min(max(target, minOffset), maxOffset)
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
        // 직전 획의 trailing 보고가 이 획 도중에 나가면 isEditing 이 풀려 보류된 레이아웃이 획 중간에 적용된다.
        // 취소하고, 미보고 변경(hasUnreportedChange)은 이 도구 사용이 끝난 뒤 함께 보고한다.
        trailingEditTask?.cancel()
        cancelCheckTask?.cancel()
        onEvent?(.editBegan)
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        cancelCheckTask?.cancel()
        if hasUnreportedChange {
            // 직전 획의 보고가 이 획 시작에 취소됐다. 이번 획이 변경을 만들면 canvasViewDrawingDidChange 가 다시 예약하므로
            // 마지막 변경까지 한 번에 보고되고, 변경이 없었다면(탭 등) 여기서 예약한 보고가 직전 획을 실어 나간다.
            scheduleTrailingEdit()
            return
        }
        // 변경 없이 끝난 도구 사용(탭 등)은 editEnded 가 오지 않으므로, 잠시 뒤에도 변경이 없으면 취소로 알린다.
        cancelCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.cancelCheckInterval ?? 0.35))
            guard let self, !Task.isCancelled, !self.hasUnreportedChange else { return }
            self.onEvent?(.editCancelled)
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing else { return }
        hasUnreportedChange = true
        cancelCheckTask?.cancel()
        if let history = isPerformingHistory {
            unreportedReason = history
        } else {
            unreportedReason = canvasView.tool is PKEraserTool ? .erase : .ink
        }
        // 제스처의 마지막 변경까지 반드시 포함시키기 위한 trailing debounce (§7-5).
        scheduleTrailingEdit()
    }

    private func scheduleTrailingEdit() {
        trailingEditTask?.cancel()
        trailingEditTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(self?.editSettleInterval ?? 0.3))
            guard let self, !Task.isCancelled, self.hasUnreportedChange else { return }
            self.hasUnreportedChange = false
            self.onEvent?(.editEnded(self.makeSnapshot(generation: self.appliedRevision)))
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
