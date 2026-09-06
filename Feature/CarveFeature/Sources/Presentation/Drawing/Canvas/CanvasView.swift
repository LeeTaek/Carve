//
//  CanvasView.swift
//  FeatureCarve
//
//  Created by 이택성 on 2/23/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import CarveToolkit
import PencilKit
import SwiftUI
import Combine

import ComposableArchitecture

//@available(*, deprecated, message: "CombinedCanvasView / CombinedCanvasFeature로 대체")
public struct CanvasView: UIViewRepresentable {
    public typealias UIViewType = PKCanvasView
    private var store: StoreOf<CanvasFeature>
    /// 설계 §6-2 입력 게이트 (Phase 2).
    ///
    /// false 면 `drawingGestureRecognizer` 를 꺼서 펜 입력을 막는다. `PKCanvasViewDrawingPolicy` 에는
    /// "입력 금지" 값이 없으므로(§16 SDK 확인) 제스처 인식기가 유일한 게이트 수단이다.
    /// 장 전체 레이아웃(`ChapterLayout`)이 전 절 측정으로 완성되기 전에는 닫혀 있다.
    private let isInputEnabled: Bool

    init(store: StoreOf<CanvasFeature>, isInputEnabled: Bool = true) {
        self.store = store
        self.isInputEnabled = isInputEnabled
    }
    
    public func makeUIView(context: Context) -> PKCanvasView {

        let canvas: PKCanvasView = {
            let canvas = PKCanvasView()

            canvas.drawingPolicy = .pencilOnly
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.translatesAutoresizingMaskIntoConstraints = false
            canvas.becomeFirstResponder()
            
            return canvas
        }()
        canvas.drawing = displayDrawing()
        canvas.drawingGestureRecognizer.isEnabled = isInputEnabled
        canvas.delegate = context.coordinator
        context.coordinator.bind(to: canvas)
        
        return canvas
    }
    
    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawingGestureRecognizer.isEnabled != isInputEnabled {
            uiView.drawingGestureRecognizer.isEnabled = isInputEnabled
        }
        Task { @MainActor in
            let newDrawing = displayDrawing()
            if uiView.drawing != newDrawing {
                uiView.drawing = newDrawing
            }
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }
    
    final public class Coordinator: NSObject, PKCanvasViewDelegate {
        private var store: StoreOf<CanvasFeature>
        /// 마지막으로 저장한 시각.
        private var lastUpdate = Date()
        /// leading-edge throttle 간격. 필기 중 과도한 저장을 막는 용도다.
        /// (이전 이름은 `debounceInterval`이었지만 동작은 debounce가 아니라 throttle이다.)
        private let throttleInterval: TimeInterval = 0.3
        /// 마지막 변경을 반드시 저장하기 위한 trailing-edge debounce 작업.
        private var trailingSaveTask: Task<Void, Never>?
        private var cancaellable = Set<AnyCancellable>()

        init(store: StoreOf<CanvasFeature>) {
            self.store = store
        }

        deinit {
            trailingSaveTask?.cancel()
        }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let now = Date()
            if now.timeIntervalSince(lastUpdate) > throttleInterval {
                lastUpdate = now
                self.store.send(.saveDrawing(canvasView.drawing))
                self.store.send(.registUndoCanvas(canvasView))
            }
            scheduleTrailingSave(for: canvasView)
        }

        /// 마지막 변경 이후 `throttleInterval` 이 지나면 최종 상태를 한 번 더 저장한다.
        ///
        /// 위의 leading-edge throttle 만으로는 제스처의 **마지막** 변경이 버려진다.
        /// 특히 지우개로 마지막 획까지 지운 결과가 저장되지 않아, 앱을 재기동하면 지웠던 획이 되살아났다.
        /// (`canvasViewDidEndUsingTool` 은 PencilKit 이 획을 `drawing` 에 반영하기 **전에** 호출되므로
        ///  최종 상태 저장 지점으로 쓸 수 없다.)
        /// undo 스택은 기존 동작을 유지하기 위해 여기서 추가로 등록하지 않는다.
        private func scheduleTrailingSave(for canvasView: PKCanvasView) {
            trailingSaveTask?.cancel()
            let delay = throttleInterval
            trailingSaveTask = Task { @MainActor [weak self, weak canvasView] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled,
                      let self,
                      let canvasView
                else { return }
                self.lastUpdate = Date()
                self.store.send(.saveDrawing(canvasView.drawing))
            }
        }

        public func bind(to canvas: PKCanvasView) {
            store.$pencilConfig.publisher
                .sink { pencil in
                    let tool: PKTool = pencil.pencilType == .monoline
                    ? PKEraserTool(.bitmap)
                    : PKInkingTool(
                        pencil.pencilType,
                        color: pencil.lineColor.color,
                        width: pencil.lineWidth
                    )
                    canvas.tool = tool
                }
                .store(in: &cancaellable)
            
            store.$allowFingerDrawing.publisher
                .sink { allow in
                    canvas.drawingPolicy = allow ? .anyInput : .pencilOnly
                }
                .store(in: &cancaellable)
        }
    }
    
    /// 저장 행을 캔버스 로컬 좌표로 옮긴 drawing. 단일 Canvas 가 첫 밑줄 원점으로 저장한 행(v3)은 첫 밑줄만큼 내린다 (§10-3 flag off).
    private func displayDrawing() -> PKDrawing {
        let stored = toDrawing(from: store.drawing?.lineData)
        let transform = store.displayTransform
        return transform.isIdentity ? stored : stored.transformed(using: transform)
    }

    private func toDrawing(from data: Data?) -> PKDrawing {
        guard let data else { return PKDrawing() }
        do {
            let drawing = try PKDrawing.init(data: data)
            return drawing
        } catch {
            Log.debug("Data to Drawing Error", error)
        }
        return PKDrawing()
    }
    
}
