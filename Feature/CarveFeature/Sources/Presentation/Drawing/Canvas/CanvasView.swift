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

// N-Canvas(절마다 PKCanvasView) 경로. 단일 Canvas 는 ChapterCanvasView 가 대체하며, flag off 롤백용으로 유지한다 (설계 §10-3).
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
        // delegate 는 아래에서 붙으므로 이 대입은 콜백을 부르지 않지만, 순서가 바뀌어도 안전하도록 같은 경로로 넣는다.
        context.coordinator.applyProgrammatically(displayDrawing(), to: canvas)
        canvas.drawingGestureRecognizer.isEnabled = isInputEnabled
        canvas.delegate = context.coordinator
        context.coordinator.bind(to: canvas)
        
        return canvas
    }
    
    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawingGestureRecognizer.isEnabled != isInputEnabled {
            uiView.drawingGestureRecognizer.isEnabled = isInputEnabled
        }
        let coordinator = context.coordinator
        Task { @MainActor in
            let newDrawing = displayDrawing()
            if uiView.drawing != newDrawing {
                // 여기가 R23 의 발화 지점이었다 — delegate 가 이미 붙어 있어 대입이 편집으로 보고됐다.
                coordinator.applyProgrammatically(newDrawing, to: uiView)
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
        /// 프로그램이 `canvas.drawing` 을 대입하는 동안 켜진다.
        ///
        /// PencilKit 은 사용자 입력뿐 아니라 **프로그램 대입에도** `canvasViewDrawingDidChange` 를 부른다.
        /// 그 콜백이 그대로 `.saveDrawing` 으로 이어지면 장을 **열기만 해도** 저장이 일어나,
        /// v3 행이 v2 로 강등되고 `layoutMetadataData` 가 지워진다 — 설계 §10-3 은 **편집할 때만** 강등이다.
        /// 단일 Canvas 는 같은 자리를 `ChapterCanvasController.isApplyingDrawing` 으로 막는다.
        private var isApplyingDrawing = false

        init(store: StoreOf<CanvasFeature>) {
            self.store = store
        }

        deinit {
            trailingSaveTask?.cancel()
        }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // 프로그램 대입은 편집이 아니다 (설계 §10-3).
            guard !isApplyingDrawing else { return }
            let now = Date()
            if now.timeIntervalSince(lastUpdate) > throttleInterval {
                lastUpdate = now
                self.store.send(.saveDrawing(canvasView.drawing))
                self.store.send(.registUndoCanvas(canvasView))
            }
            scheduleTrailingSave(for: canvasView)
        }

        /// 표시용 drawing 을 캔버스에 대입한다. 이 구간의 delegate 콜백은 편집으로 보고하지 않는다.
        ///
        /// 사용자 편집으로 예약된 trailing save 는 취소하지 않는다 — 취소하면 그 편집을 잃는다.
        /// 편집이 먼저 store 에 반영되면 `displayDrawing()` 이 캔버스 내용과 같아져 이 대입 자체가 일어나지 않는다.
        /// - Parameters:
        ///   - drawing: 대입할 drawing.
        ///   - canvasView: 대상 캔버스.
        @MainActor
        func applyProgrammatically(_ drawing: PKDrawing, to canvasView: PKCanvasView) {
            isApplyingDrawing = true
            canvasView.drawing = drawing
            isApplyingDrawing = false
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
