//
//  CombinedCanvasView.swift
//  CarveFeature
//
//  Created by 이택성 on 11/4/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Combine
import SwiftUI
import PencilKit
import Domain
import CarveToolkit

import ComposableArchitecture

import UIKit
import QuartzCore


final class StableCanvasView: PKCanvasView {
  var onPencilDown: (() -> Void)?
  var onPencilUp: (() -> Void)?

  private var hasPencilContact: Bool = false
    private var isHovering: Bool = false
    
  private func dump(_ tag: String) {
    #if DEBUG
    let screenScale = window?.screen.scale ?? UIScreen.main.scale
    print("""
    🧪 \(tag)
      bounds: \(bounds), frame: \(frame)
      contentScaleFactor: \(contentScaleFactor)
      layer.contentsScale: \(layer.contentsScale)
      window.screen.scale: \(screenScale)
      trait.displayScale: \(traitCollection.displayScale)
      sublayers: \(layer.sublayers?.count ?? 0)
    """)

    if let sublayers = layer.sublayers {
      for (index, sublayer) in sublayers.prefix(6).enumerated() {
        print("    sub[\(index)] contentsScale=\(sublayer.contentsScale) bounds=\(sublayer.bounds) transform=\(sublayer.transform)")
      }
    }

    // What is actually rendered on-screen right now (presentation layer)
    if let presentationLayer = layer.presentation() {
      let affineTransform = CATransform3DGetAffineTransform(presentationLayer.transform)
      print("    [presentation] layer.affineTransform=\(affineTransform) bounds=\(presentationLayer.bounds) position=\(presentationLayer.position) contentsScale=\(presentationLayer.contentsScale)")
    }

    if let sublayers = layer.sublayers {
      for (index, sublayer) in sublayers.prefix(6).enumerated() {
        if let subPresentationLayer = sublayer.presentation() {
          let affineTransform = CATransform3DGetAffineTransform(subPresentationLayer.transform)
          print("    [presentation] sub[\(index)].affineTransform=\(affineTransform) bounds=\(subPresentationLayer.bounds) position=\(subPresentationLayer.position) contentsScale=\(subPresentationLayer.contentsScale)")
        }
      }
    }

    print("    rasterize: should=\(layer.shouldRasterize) scale=\(layer.rasterizationScale) drawsAsync=\(layer.drawsAsynchronously)")
      
      print("""
        zoomScale: \(zoomScale)
        minimumZoomScale: \(minimumZoomScale)
        maximumZoomScale: \(maximumZoomScale)
        contentOffset: \(contentOffset)
        contentSize: \(contentSize)
        adjustedContentInset: \(adjustedContentInset)
      """)
    #endif
  }
    
    /// hover/inking 중에도 안전하게 동기화 가능한 최소치: contentSize만 bounds에 맞춘다.
    private func syncContentSizeToBounds() {
      let target = bounds.size
      guard target.width > 0, target.height > 0 else { return }
      if contentSize != target {
        UIView.performWithoutAnimation { self.contentSize = target }
      }
    }

    /// hover/inking이 아닐 때만 “리셋” (offset/inset/zoom)
    private func resetScrollStateToIdentity() {
      UIView.performWithoutAnimation {
        if contentInset != .zero { contentInset = .zero }
        if scrollIndicatorInsets != .zero { scrollIndicatorInsets = .zero }
        if contentOffset != .zero { contentOffset = .zero }

        if minimumZoomScale != 1 { minimumZoomScale = 1 }
        if maximumZoomScale != 1 { maximumZoomScale = 1 }
        if zoomScale != 1 { zoomScale = 1 }
      }
    }
    
    
  /// 화면 스케일(예: 2.0/3.0)에 맞춰 UIView + 내부 레이어 스케일 동기화
  private func syncScaleToWindow() {
    let screenScale = window?.screen.scale ?? UIScreen.main.scale

    // Prevent implicit animations that can look like a zoom.
    UIView.performWithoutAnimation {
      CATransaction.begin()
      CATransaction.setDisableActions(true)

      // 1) Sync this view
      if contentScaleFactor != screenScale { contentScaleFactor = screenScale }
      if layer.contentsScale != screenScale { layer.contentsScale = screenScale }

      // 2) Sync all subviews' contentScaleFactor + layer.contentsScale
      func applyViewScale(_ view: UIView) {
        if view.contentScaleFactor != screenScale { view.contentScaleFactor = screenScale }
        if view.layer.contentsScale != screenScale { view.layer.contentsScale = screenScale }

        // If this is backed by a CAMetalLayer, also ensure drawableSize matches pixels.
        if let metalLayer = view.layer as? CAMetalLayer {
          if metalLayer.contentsScale != screenScale { metalLayer.contentsScale = screenScale }
          let pixelSize = CGSize(width: view.bounds.width * screenScale, height: view.bounds.height * screenScale)
          if metalLayer.drawableSize != pixelSize {
            metalLayer.drawableSize = pixelSize
          }
        }

        view.subviews.forEach(applyViewScale)
      }

      // 3) Also recursively sync layer.contentsScale for the whole layer subtree
      func applyLayerScale(_ targetLayer: CALayer) {
          if targetLayer.contentsScale != screenScale { targetLayer.contentsScale = screenScale }

           if let metalLayer = targetLayer as? CAMetalLayer {
             if metalLayer.contentsScale != screenScale { metalLayer.contentsScale = screenScale }
             let pixelSize = CGSize(
               width: targetLayer.bounds.width * screenScale,
               height: targetLayer.bounds.height * screenScale
             )
             if metalLayer.drawableSize != pixelSize {
               metalLayer.drawableSize = pixelSize
             }
           }

           targetLayer.sublayers?.forEach(applyLayerScale)
      }
      applyLayerScale(layer)

      CATransaction.commit()
    }
  }

  /// PKCanvasView(UIScrollView) 내부 geometry가 0이거나 어긋나면 라이브 스트로크가 확대/오프셋된 것처럼 보일 수 있어
  /// bounds 기반으로 최소한의 scroll geometry를 고정한다.
  private func syncScrollGeometryToBounds() {
    UIView.performWithoutAnimation {
      // contentSize가 (0,0)인 상태는 라이브 렌더러가 잘못된 스케일/오프셋으로 그릴 가능성이 큼
      let targetSize = bounds.size
      if targetSize.width > 0, targetSize.height > 0 {
        if contentSize != targetSize {
          contentSize = targetSize
        }
      }

      if contentInset != .zero { contentInset = .zero }
      if scrollIndicatorInsets != .zero { scrollIndicatorInsets = .zero }
      if contentOffset != .zero { contentOffset = .zero }

      if minimumZoomScale != 1 { minimumZoomScale = 1 }
      if maximumZoomScale != 1 { maximumZoomScale = 1 }
      if zoomScale != 1 { zoomScale = 1 }
    }
  }

    private func dumpChangedLayers(rootLayer: CALayer, depth: Int, maxDepth: Int) {
      guard depth <= maxDepth else { return }

      if let presentationLayer = rootLayer.presentation() {
        let affineTransform = CATransform3DGetAffineTransform(presentationLayer.transform)
        let isScaled = abs(affineTransform.a - 1.0) > 0.0001 || abs(affineTransform.d - 1.0) > 0.0001
        let isTranslated = abs(affineTransform.tx) > 0.5 || abs(affineTransform.ty) > 0.5

        if isScaled || isTranslated {
          print("🔎 depth=\(depth) affine=\(affineTransform) bounds=\(presentationLayer.bounds) position=\(presentationLayer.position) class=\(type(of: rootLayer))")
        }
      }

      rootLayer.sublayers?.forEach { childLayer in
        dumpChangedLayers(rootLayer: childLayer, depth: depth + 1, maxDepth: maxDepth)
      }
    }

    /// PKCanvasView의 라이브 렌더링은 subview 레벨에서 변할 수 있어 내부 subviews를 덤프한다.
    private func dumpSubviews(_ tag: String) {
      #if DEBUG
      func approxEqual(_ one: CGSize, _ two: CGSize, tol: CGFloat = 0.5) -> Bool {
        abs(one.width - two.width) <= tol && abs(one.height - two.height) <= tol
      }

      func dumpMetalLayers(in layer: CALayer, screenScale: CGFloat, depth: Int) {
        let indent = String(repeating: "  ", count: depth)

        if let metal = layer as? CAMetalLayer {
          let expected = CGSize(width: layer.bounds.width * screenScale,
                                height: layer.bounds.height * screenScale)
          let mismatch = !approxEqual(metal.drawableSize, expected)
          let mark = mismatch ? "⚠️" : "  "
          print("\(indent)\(mark)🔩 CAMetalLayer bounds=\(layer.bounds) drawableSize=\(metal.drawableSize) expected=\(expected) contentsScale=\(metal.contentsScale)")
        }

        layer.sublayers?.forEach { dumpMetalLayers(in: $0, screenScale: screenScale, depth: depth + 1) }
      }

      func describe(_ view: UIView, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        let screenScale = view.window?.screen.scale ?? UIScreen.main.scale
        let pres = view.layer.presentation().map { CATransform3DGetAffineTransform($0.transform) }

        print("\(indent)🧩 [\(tag)] \(type(of: view)) frame=\(view.frame) bounds=\(view.bounds) csf=\(view.contentScaleFactor) layerScale=\(view.layer.contentsScale) windowScale=\(screenScale) pres=\(String(describing: pres))")
        print("\(indent)  🧬 layerClass=\(type(of: view.layer)) sublayers=\(view.layer.sublayers?.count ?? 0)")

        // ✅ 여기서 layer subtree CAMetalLayer 탐색
        dumpMetalLayers(in: view.layer, screenScale: screenScale, depth: depth + 1)

        view.subviews.forEach { describe($0, depth: depth + 1) }
      }

      describe(self, depth: 0)
      #endif
    }

    /// SwiftUI/ScrollView/overlay 레이아웃 과정에서 상위 뷰 체인에 scale/translate transform이 걸리면
    /// PencilKit의 입력 좌표와 렌더링 좌표가 어긋나며, 폭이 좁아질수록 오차가 커지는 현상이 발생할 수 있다.
    /// 상위 뷰/레이어의 실제(=presentation) transform까지 포함해 덤프한다.
    private func dumpSuperviewTransforms(_ tag: String) {
      #if DEBUG
      func isIdentity(_ transform: CGAffineTransform) -> Bool {
        abs(transform.a - 1) < 0.0001 && abs(transform.d - 1) < 0.0001 && abs(transform.b) < 0.0001 && abs(transform.c) < 0.0001 && abs(transform.tx) < 0.5 && abs(transform.ty) < 0.5
      }

      print("🧭 [\(tag)] superview transform chain")
      var currentView: UIView? = self
      var depth = 0
      while let view = currentView, depth < 16 {
        let presAffine = view.layer.presentation().map { CATransform3DGetAffineTransform($0.transform) }
        let viewTransform = view.transform
        let layerAffine = CATransform3DGetAffineTransform(view.layer.transform)

        // If anything looks non-identity, we highlight it.
        let flagged = !isIdentity(viewTransform) || !isIdentity(layerAffine) || (presAffine.map { !isIdentity($0) } ?? false)
        let mark = flagged ? "⚠️" : "  "

        print("\(mark) [\(depth)] \(type(of: view)) frame=\(view.frame) bounds=\(view.bounds)")
        print("\(mark)      view.transform=\(viewTransform)")
        print("\(mark)      layer.affine(from model)=\(layerAffine)")
        if let presAffine {
          print("\(mark)      layer.affine(from presentation)=\(presAffine)")
        } else {
          print("\(mark)      layer.affine(from presentation)=nil")
        }

        currentView = view.superview
        depth += 1
      }
      #endif
    }
    
  override func didMoveToWindow() {
    super.didMoveToWindow()
    syncScaleToWindow()
    syncScrollGeometryToBounds()
    dump("didMoveToWindow")
    dumpSubviews("didMoveToWindow")
    dumpSuperviewTransforms("didMoveToWindow")
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    addHoverLogger()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    addHoverLogger()
  }

  private func addHoverLogger() {
    let hover = UIHoverGestureRecognizer(target: self, action: #selector(onHover(_:)))
    addGestureRecognizer(hover)
  }

  private var lastHoverLogTimestamp: CFTimeInterval = 0
  private let hoverLogInterval: CFTimeInterval = 0.25

  /// 화면 scale과 불일치하는(=1.0으로 떨어진) 내부 뷰/레이어를 빠르게 찾기 위한 로그
    private func dumpScaleMismatches(_ tag: String) {
    #if DEBUG
      let screenScale = window?.screen.scale ?? UIScreen.main.scale

      func approxEqual(_ one: CGSize, _ two: CGSize, tol: CGFloat = 0.5) -> Bool {
        abs(one.width - two.width) <= tol && abs(one.height - two.height) <= tol
      }

      func visitLayer(_ layer: CALayer, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        if let metal = layer as? CAMetalLayer {
          let expected = CGSize(width: layer.bounds.width * screenScale,
                                height: layer.bounds.height * screenScale)
          if !approxEqual(metal.drawableSize, expected) {
            print("\(indent)🔩 [\(tag)] CAMetalLayer mismatch bounds=\(layer.bounds) drawableSize=\(metal.drawableSize) expected=\(expected) contentsScale=\(metal.contentsScale)")
          }
        }
        layer.sublayers?.forEach { visitLayer($0, depth: depth + 1) }
      }

      func visitView(_ view: UIView, depth: Int) {
        let indent = String(repeating: "  ", count: depth)

        if abs(view.contentScaleFactor - screenScale) > 0.0001 ||
           abs(view.layer.contentsScale - screenScale) > 0.0001 {
          print("\(indent)🧷 [\(tag)] View scale mismatch \(type(of: view)) csf=\(view.contentScaleFactor) layerScale=\(view.layer.contentsScale) expected=\(screenScale)")
        }

        visitLayer(view.layer, depth: depth)
        view.subviews.forEach { visitView($0, depth: depth + 1) }
      }

      visitView(self, depth: 0)
    #endif
    }
    

  override func didAddSubview(_ subview: UIView) {
    super.didAddSubview(subview)

    // PencilKit이 hover/inking 시점에 내부 subview를 추가하면서 scale을 1.0으로 두는 경우가 있어
    // 추가되는 즉시 다시 맞춰준다.
    syncScaleToWindow()
    syncScrollGeometryToBounds()

    #if DEBUG
    let screenScale = window?.screen.scale ?? UIScreen.main.scale
    if abs(subview.contentScaleFactor - screenScale) > 0.0001 || abs(subview.layer.contentsScale - screenScale) > 0.0001 {
      print("➕ didAddSubview: \(type(of: subview)) csf=\(subview.contentScaleFactor) layerScale=\(subview.layer.contentsScale) expected=\(screenScale)")
    }
    #endif
  }
    
    @objc private func onHover(_ gestureRecognizer: UIHoverGestureRecognizer) {
      switch gestureRecognizer.state {
      case .began, .changed:
        isHovering = true
        // ✅ hover 중에는 스케일은 맞추되, scroll 리셋(offset/inset/zoom)은 건드리지 않는다.
        syncScaleToWindow()
        // ✅ 다만 PKCanvasView(UIScrollView)의 contentSize는 bounds와 항상 일치시켜
        // 라이브 렌더러(hover/inking)가 잘못된 타일/버퍼 크기를 잡아 “확대처럼 보이는” 현상을 막는다.
        if !hasPencilContact {
          syncContentSizeToBounds()
        }

        #if DEBUG
        let now = CACurrentMediaTime()
        if now - lastHoverLogTimestamp >= hoverLogInterval {
          lastHoverLogTimestamp = now
          dump("hover")
          dumpScaleMismatches("hover")
          dumpSuperviewTransforms("hover")
          dumpChangedLayers(rootLayer: layer, depth: 0, maxDepth: 10)
            dumpSubviews("hover")     // ✅ hover 때 새로 생긴 subview/metal layer 확인
        }
        #endif

      default:
        isHovering = false
        // hover 끝난 다음 프레임에 한 번만 정리 (레이스 방지)
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          guard self.isHovering == false, self.hasPencilContact == false else { return }
          self.syncScaleToWindow()
          self.syncScrollGeometryToBounds()
        }
      }
        if isHovering && contentSize != bounds.size {
          print("⚠️ hover mismatch: bounds=\(bounds.size) contentSize=\(contentSize)")
        }
    }

    
    private var lastBounds: CGRect = .zero
    private var lastContentSize: CGSize = .zero
    private var lastContentOffset: CGPoint = .zero
    
    override func layoutSubviews() {
      super.layoutSubviews()

      // PKCanvasView는 UIScrollView 기반이라 bounds가 변해도 contentSize가 이전 값으로 남으면
      // hover/라이브 스트로크에서 내부 렌더 버퍼가 커진 것처럼 잡혀 “확대/오프셋”처럼 보일 수 있다.
      // offset/inset/zoom은 건드리지 않고, contentSize만 bounds에 맞춘다.
      if !hasPencilContact {
        syncContentSizeToBounds()
      }

      if isHovering || hasPencilContact {
        if bounds != lastBounds || contentSize != lastContentSize || contentOffset != lastContentOffset {
          print("🧪 change hover=\(isHovering) pencil=\(hasPencilContact) bounds \(lastBounds) -> \(bounds) contentSize \(lastContentSize) -> \(contentSize) offset \(lastContentOffset) -> \(contentOffset)")
          lastBounds = bounds
          lastContentSize = contentSize
          lastContentOffset = contentOffset
        }
      }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesBegan(touches, with: event)
      if touches.contains(where: { $0.type == .pencil }) {
        // 시작 콜백은 즉시
        if !hasPencilContact {
          onPencilDown?()
        }
        hasPencilContact = true
        syncScaleToWindow()
        // ✅ pencilDown에서도 offset/inset/zoom은 건드리지 않고, contentSize만 bounds에 맞춘다.
        // syncContentSizeToBounds()  // 🚫 do not call during inking
        dump("pencilDown")
        dumpSuperviewTransforms("pencilDown")
      }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesEnded(touches, with: event)
      if touches.contains(where: { $0.type == .pencil }) {
        hasPencilContact = false
        // ✅ 펜을 뗀 후에만 geometry 정리
        syncScaleToWindow()
        syncScrollGeometryToBounds()
        dump("pencilUp")
        dumpSuperviewTransforms("pencilUp")

        // 종료 콜백은 다음 런루프에(마지막 스트로크 커밋 이후)
        DispatchQueue.main.async { [weak self] in
          self?.onPencilUp?()
        }
      }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesCancelled(touches, with: event)
      if touches.contains(where: { $0.type == .pencil }) {
        hasPencilContact = false
        syncScaleToWindow()
        syncScrollGeometryToBounds()
        dump("pencilCancel")

        DispatchQueue.main.async { [weak self] in
          self?.onPencilUp?()
        }
      }
    }
    
    
}

public struct CombinedCanvasView: UIViewRepresentable {
    public typealias UIViewType = PKCanvasView
    private var store: StoreOf<CombinedCanvasFeature>
    private var onInkingChanged: ((Bool) -> Void)?

    init(
      store: StoreOf<CombinedCanvasFeature>,
      onInkingChanged: ((Bool) -> Void)? = nil
    ) {
      self.store = store
      self.onInkingChanged = onInkingChanged
    }
    

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas: StableCanvasView = {
            let canvas = StableCanvasView()

            canvas.drawingPolicy = .pencilOnly
            canvas.backgroundColor = .clear
            canvas.isOpaque = false

            // PKCanvasView는 UIScrollView 기반이라 inset/offset/zoom이 생기면
            // '그리는 중' 라이브 스트로크/기존 스트로크가 확대·이동된 것처럼 보였다가
            // 펜을 떼면 커밋되며 원래 위치로 스냅하는 현상이 생길 수 있음.
            canvas.isScrollEnabled = false
            canvas.bounces = false
            canvas.alwaysBounceVertical = false
            canvas.alwaysBounceHorizontal = false
            canvas.contentInsetAdjustmentBehavior = .never
            canvas.contentInset = .zero
            canvas.scrollIndicatorInsets = .zero
            canvas.contentOffset = .zero
            canvas.minimumZoomScale = 1
            canvas.maximumZoomScale = 1
            canvas.zoomScale = 1
            canvas.bouncesZoom = false
            canvas.pinchGestureRecognizer?.isEnabled = false

            return canvas
        }()
        canvas.drawing = store.combinedDrawing
        canvas.delegate = context.coordinator
        context.coordinator.bind(to: canvas)

        let onInkingChanged = self.onInkingChanged

        // ✅ hover가 아니라 "실제 pencil touch"로만 inking 시작/종료를 추적
        canvas.onPencilDown = { [weak coordinator = context.coordinator, weak canvas] in
            guard let coordinator, let canvas else { return }
            onInkingChanged?(true)
            coordinator.pencilDidBegin(on: canvas)
        }
        canvas.onPencilUp = { [weak coordinator = context.coordinator, weak canvas] in
            guard let coordinator, let canvas else { return }
            coordinator.pencilDidEnd(on: canvas)
            onInkingChanged?(false)
        }

        canvas.delaysContentTouches = false
        canvas.canCancelContentTouches = false

        return canvas
    }

    // iOS 17+: SwiftUI가 제안한 크기를 그대로 사용하도록 해서
    // PKCanvasView의 intrinsic/contentSize 변화가 레이아웃에 영향을 주지 않게 만든다.
    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: PKCanvasView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let height = proposal.height ?? uiView.bounds.height
        return CGSize(width: width, height: height)
    }

    public func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // 라이브 스트로크/hover 중에는 레이아웃/스크롤뷰 값을 만지면 오히려 "확대/오프셋"이 생길 수 있어
        // updateUIView에서는 contentSize 등 사이징을 절대 강제하지 않는다.
        // 필요한 최소 설정은 makeUIView에서 1회만 세팅한다.
    }
    
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    final public class Coordinator: NSObject, PKCanvasViewDelegate {
        private var store: StoreOf<CombinedCanvasFeature>
        /// Debounce 적용을 위한 이전 Update 타이밍
        private var lastUpdate = Date()
        /// drawing Data update를 위한 Debounce 시간
        private let debounceInterval: TimeInterval = 0.3
        /// publisher sink cancellable
        private var cancellables = Set<AnyCancellable>()
        /// 이전 stroke 수
        private var previousStrokeCount = 0
        /// 실제 pencil touch 기반으로 inking 여부
        fileprivate var isInking = false
        /// 펜을 대고 있는 동안 누적되는 변경 영역(저장은 펜을 뗄 때 한 번만)
        private var pendingChangedRect: CGRect = .null


        init(store: StoreOf<CombinedCanvasFeature>) {
            self.store = store
        }
        
        func pencilDidBegin(on canvasView: PKCanvasView) {
            isInking = true
            pendingChangedRect = .null
            previousStrokeCount = canvasView.drawing.strokes.count
        }

        func pencilDidEnd(on canvasView: PKCanvasView) {
            // 펜을 뗄 때 한 번만 저장
            if !pendingChangedRect.isNull, !pendingChangedRect.isEmpty {
                store.send(.saveDrawing(canvasView.drawing, pendingChangedRect))
            }

            pendingChangedRect = .null
            isInking = false
            previousStrokeCount = canvasView.drawing.strokes.count
            notifyUndoState(from: canvasView)
        }
        
        public func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // NOTE: Apple Pencil hover에서도 호출될 수 있으므로 여기서는 상태를 바꾸지 않는다.
            Log.debug("zoomScale", canvasView.zoomScale)
            Log.debug("contentOffset", canvasView.contentOffset)
            Log.debug("adjustedInset", canvasView.adjustedContentInset)
        }

        public func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            // NOTE: 저장/상태 변경은 pencilDidEnd(on:)에서만 처리한다.
        }
        
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // undo/redo 중에는 save 무시
            if canvasView.undoManager?.isUndoing == true ||
                canvasView.undoManager?.isRedoing == true {
                // undo/redo로 stroke 수가 바뀌기 때문에, 다음 저장 로직이 꼬이지 않도록 동기화
                previousStrokeCount = canvasView.drawing.strokes.count
                notifyUndoState(from: canvasView)
                return
            }

            let drawingData = canvasView.drawing
            let strokesData = drawingData.strokes

            // 새로 그린 stroke 추출
            let currentStrokeCount = strokesData.count
            guard currentStrokeCount > previousStrokeCount else { return }

            let newStrokes = strokesData[previousStrokeCount..<currentStrokeCount]
            previousStrokeCount = currentStrokeCount

            // 새 stroke들의 rect 계산
            let changedRect = newStrokes.reduce(CGRect.null) { partial, stroke in
                partial.union(stroke.renderBounds)
            }
            guard !changedRect.isNull, !changedRect.isEmpty else { return }

            // 펜을 대고 있는 동안에는 저장하지 않고, 변경 영역만 누적
            pendingChangedRect = pendingChangedRect.isNull ? changedRect : pendingChangedRect.union(changedRect)
        }
        
        public func bind(to canvas: PKCanvasView) {
            // Drawing Bind
            observe { [weak self] in
                guard let self = self else { return }

                let newDrawing = self.store.combinedDrawing
                // NOTE:
                // Avoid calling `dataRepresentation()` for equality checks.
                // It is expensive and, on some OS versions, can emit logs like:
                // "retrieving stroke identifier gave nil or invalid result".
                // Our use-case appends/removes strokes (undo/redo), so stroke-count + bounds is a stable enough guard.
                let currentStrokeCount = canvas.drawing.strokes.count
                let newStrokeCount = newDrawing.strokes.count
                let boundsChanged = canvas.drawing.bounds != newDrawing.bounds

                guard currentStrokeCount != newStrokeCount || boundsChanged else {
                    return
                }
                // 펜으로 그리고 있는 동안에는 외부에서 drawing을 교체하지 않는다.
                // (교체 시 라이브 스트로크가 확대/이동된 것처럼 보일 수 있음)
                if self.isInking {
                    return
                }

                #if DEBUG
                print("🧩 apply store.combinedDrawing -> canvas (inking=\(self.isInking)) strokes=\(newDrawing.strokes.count) bounds=\(newDrawing.bounds)")
                #endif

                UIView.performWithoutAnimation {
                    canvas.drawing = newDrawing
                }
                self.previousStrokeCount = newDrawing.strokes.count
            }
            // undo상태 초기화
            notifyUndoState(from: canvas)
            
            store.publisher.undoVersion
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    canvas.undoManager?.undo()
                    self.previousStrokeCount = canvas.drawing.strokes.count
                    self.notifyUndoState(from: canvas)
                }
                .store(in: &cancellables)
            
            store.publisher.redoVersion
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    canvas.undoManager?.redo()
                    self.previousStrokeCount = canvas.drawing.strokes.count
                    self.notifyUndoState(from: canvas)
                }
                .store(in: &cancellables)

            // Pencil Config bind
            store.$pencilConfig.publisher
                .sink { pencilConfig in
                    let tool: PKTool = pencilConfig.pencilType == .monoline
                    ? PKEraserTool(.bitmap)
                    : PKInkingTool(
                        pencilConfig.pencilType,
                        color: pencilConfig.lineColor.color,
                        width: pencilConfig.lineWidth
                    )
                    UIView.performWithoutAnimation {
                        canvas.tool = tool
                    }
                }
                .store(in: &cancellables)
            
            // 손가락 입력 설정 Bind
            store.$allowFingerDrawing.publisher
                .sink { allow in
                    canvas.drawingPolicy = allow ? .anyInput : .pencilOnly
                }
                .store(in: &cancellables)
        }
        
        /// Undo/Redo 가능 여부를 Feature로 전달
        private func notifyUndoState(from canvas: PKCanvasView) {
            let canUndo = canvas.undoManager?.canUndo ?? false
            let canRedo = canvas.undoManager?.canRedo ?? false
            store.send(.undoStateChanged(canUndo: canUndo, canRedo: canRedo))
        }
    }
    
}

#Preview {
    @Previewable @State var store = Store(
        initialState: .initialState,
        reducer: { CombinedCanvasFeature() },
        withDependencies: {
            $0.drawingData = .previewValue
        }
    )
    CombinedCanvasView(store: store)
}
