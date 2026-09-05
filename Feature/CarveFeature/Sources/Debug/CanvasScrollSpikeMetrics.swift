//
//  CanvasScrollSpikeMetrics.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import CoreGraphics
import PencilKit
import QuartzCore
import SwiftUI
import UIKit

// MARK: - 스크롤 상태 스냅샷

/// `UIScrollView` 한 개의 기하 상태. HUD에 그대로 찍는다.
struct SpikeScrollSnapshot: Equatable {
    var offset: CGPoint = .zero
    var contentSize: CGSize = .zero
    var contentInset: UIEdgeInsets = .zero
    var adjustedInset: UIEdgeInsets = .zero
    var zoomScale: CGFloat = 1
    var safeArea: UIEdgeInsets = .zero
    var isAttached = false
}

// MARK: - 프로브 한 개의 측정 결과

/// 기준 절 하나에 대한 측정 결과. 모든 값의 단위는 pt.
struct SpikeProbeSample: Equatable, Identifiable {
    var id: Int { verse }
    /// 기준 절 번호.
    let verse: Int
    /// 잉크(캔버스 content 좌표)의 스크롤 불변 잔차.
    let inkResidual: CGFloat
    /// 텍스트 마커의 스크롤 불변 잔차.
    let textResidual: CGFloat
    /// 잉크-텍스트 정합이 기준 상태 대비 얼마나 어긋났는가.
    let alignDrift: CGFloat
    /// 잉크-텍스트의 현재 절대 정합 오차(기준 상태의 서브픽셀 bias 포함).
    let rawAlign: CGVector

    /// 통과 기준 1에 쓰는 대표값.
    var worst: CGFloat { max(inkResidual, max(textResidual, alignDrift)) }
}

// MARK: - 측정기

/// 스파이크 하네스의 **자체 측정기**.
///
/// ## 왜 이렇게 재는가 (측정 방법이 오차를 만들지 않기 위한 근거)
///
/// 통과 기준 1은 "스크롤 전후 동일 content point의 stroke 오차 ≤ 1pt"다.
/// 즉 `content → screen` 매핑이 **정확히 `contentOffset` 만큼의 평행이동**이어야 한다는 뜻이다.
/// 그래서 다음 두 값을 각각 UIKit의 좌표 변환으로 직접 얻는다.
///
/// 1. **잉크 쪽** — `canvas.convert(P, to: nil)`
///    `PKCanvasView`는 `UIScrollView`이고 `UIScrollView`의 content 좌표계는 곧 그 뷰의
///    `bounds` 좌표계다(`bounds.origin == contentOffset`). 따라서 캔버스 content 좌표 `P`를
///    `convert(_:to:)`에 넣으면 UIKit이 **자신의 transform 체인**(bounds origin, superview 위치,
///    safe-area로 인한 프레임 변화 포함)으로 window 좌표를 돌려준다.
///    `contentOffset` 산술을 우리가 직접 하지 않는다 — 우리가 검증하려는 가정을 측정에 쓰지 않기 위해서다.
///    `zoomScale`은 A/B 모두 1로 고정하고 HUD에 그대로 노출한다. 1이 아니면 이 등식이 깨지므로
///    화면에서 바로 확인할 수 있다.
///
/// 2. **텍스트 쪽** — 같은 content 좌표에 놓인 마커 `UIView`의 `convert(center, to: nil)`
///    마커는 A에서는 SwiftUI 텍스트 컬럼 안에, B에서는 `UIHostingController` 안에 있으므로
///    각 모드의 텍스트 호스팅 경로를 그대로 통과한 좌표가 나온다.
///
/// ## 세 가지 지표
///
/// - `inkResidual` / `textResidual` — `windowPoint − viewportOriginWindow + governingOffset`이
///   스크롤과 무관하게 일정한가. 기준 상태(첫 샘플)의 값을 절대 기준으로 잡고 그 차이를 본다.
///   순수 평행이동이면 정확히 0이다.
///   `viewportOriginWindow = scrollView.convert(scrollView.bounds.origin, to: nil)` 로,
///   **스크롤 컨테이너 자체가 화면에서 이동한 양**(헤더 접힘/펼침, safe-area 변화 등)을 뺀다.
///   기준 1이 묻는 것은 "content point → **viewport** 매핑이 offset만큼의 평행이동인가"이지
///   viewport가 화면 어디에 있는가가 아니기 때문이다. 이 항을 빼지 않으면 헤더 애니메이션만으로
///   헤더 높이만큼의 가짜 drift가 잡힌다(실측으로 확인함: 105pt = 헤더 높이).
/// - `alignDrift` — 잉크와 텍스트의 상대 위치가 기준 상태 대비 변했는가.
///   기준 상태에서의 정합 오차를 빼기 때문에 **SwiftUI의 픽셀 정렬로 생기는 고정 bias(≤0.5pt)가
///   판정값에 섞이지 않는다.** 그 고정 bias 자체는 `rawAlign`으로 따로 표시한다.
///
/// 남는 측정 잡음은 스크롤 중 프레임마다 생기는 픽셀 스냅(≤0.5pt)뿐이며 판정 임계값 1pt보다 작다.
/// 프로그램 스크롤은 정수 offset으로만 이동시켜 이 잡음도 최소화한다.
@MainActor
final class CanvasScrollSpikeMetrics: ObservableObject {
    /// 통과 기준 1의 임계값.
    static let tolerance: CGFloat = 1.0

    // 표시용 상태
    @Published private(set) var samples: [SpikeProbeSample] = []
    @Published private(set) var currentDelta: CGFloat = 0
    @Published private(set) var peakDelta: CGFloat = 0
    @Published private(set) var returnDelta: CGFloat?
    @Published private(set) var scrollEventCount: Int = 0
    @Published private(set) var governing = SpikeScrollSnapshot()
    @Published private(set) var canvasState = SpikeScrollSnapshot()
    @Published private(set) var tapCount: Int = 0
    @Published private(set) var longPressCount: Int = 0
    /// 스크롤 컨테이너 좌상단의 window 좌표. 측정에서 빼는 항이라 HUD에 그대로 노출한다.
    @Published private(set) var viewportOriginInWindow: CGPoint = .zero
    /// 캔버스에 실제로 붙어 있는 제스처 인식기 상태.
    /// 통과 기준 5(탭/롱프레스)와 9·10(필기 정책 대 스크롤)의 **구조적 전제**를 눈으로 확인하는 용도다.
    /// 행동 확인은 실제 터치가 필요하므로 이 줄만으로 기준 9·10을 통과 판정하지 않는다.
    @Published private(set) var gestureSummary: String = "-"
    @Published private(set) var note: String = "대기 중"
    @Published private(set) var restoreReport: String = "-"
    @Published private(set) var sampleCount: Int = 0
    /// 단계별 판정 결과. `resetReference`로 지워지지 않으므로 **스크린샷 한 장에 전체 시나리오 결과가 남는다.**
    @Published private(set) var results: [String] = []

    // 측정 대상 (약참조 — 뷰 재생성 시 자동으로 끊긴다)
    private weak var canvas: PKCanvasView?
    private weak var governingScrollView: UIScrollView?
    private var markers: [Int: WeakMarker] = [:]
    /// 캔버스 content 좌표 = layout 좌표 + `columnOrigin`.
    private var columnOrigin: CGPoint = .zero
    private var probePoints: [Int: CGPoint] = [:]

    // 기준 상태
    private var reference: [Int: ReferenceEntry] = [:]

    private var displayLink: CADisplayLink?
    private var lastPublish: CFTimeInterval = 0
    /// `@Published` 갱신은 10Hz로 낮추고, 아래 값들은 매 프레임 누적한다.
    /// 순간적으로만 어긋나는 drift를 놓치지 않으면서 SwiftUI 재렌더 비용을 피하기 위함이다.
    private var peakDeltaValue: CGFloat = 0
    private var sampleCountValue: Int = 0
    private var offsetChangeCount: Int = 0
    private var lastOffset = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    private var lastWorst: CGFloat = 0

    private struct WeakMarker {
        weak var view: UIView?
    }

    private struct ReferenceEntry {
        let inkAbsolute: CGPoint
        let textAbsolute: CGPoint
        let align: CGVector
    }

    // MARK: 대상 등록

    /// 측정 대상 갱신. 모드 전환·재진입 때마다 호출된다.
    func attach(canvas: PKCanvasView?, governing: UIScrollView?, columnOrigin: CGPoint) {
        self.canvas = canvas
        self.governingScrollView = governing
        self.columnOrigin = columnOrigin
    }

    /// 기준 절의 캔버스 content 좌표(layout 좌표) 등록.
    func setProbePoints(_ points: [Int: CGPoint]) {
        probePoints = points
        resetReference(note: "프로브 재설정")
    }

    /// 텍스트 컬럼 안에 놓인 마커 뷰 등록.
    func registerMarker(verse: Int, view: UIView?) {
        if let view {
            markers[verse] = WeakMarker(view: view)
        } else {
            markers[verse] = nil
        }
        reference[verse] = nil
    }

    /// 기준 상태 초기화. 스크롤 원점에서 다시 잡는 것이 원칙이다.
    func resetReference(note: String) {
        reference.removeAll()
        peakDeltaValue = 0
        peakDelta = 0
        returnDelta = nil
        self.note = note
    }

    /// 기준 상태는 유지한 채 peak만 다시 잡는다. 단계별 측정에 쓴다.
    func resetPeak() {
        peakDeltaValue = 0
        peakDelta = 0
        returnDelta = nil
    }

    /// 단계 결과를 한 줄 남긴다.
    func appendResult(_ label: String, delta: CGFloat?) {
        let index = results.count + 1
        guard let delta else {
            results.append("[\(index)] \(label)")
            return
        }
        let verdict = delta <= Self.tolerance ? "PASS" : "FAIL"
        results.append(String(format: "[%d] %@  max %.3fpt  %@", index, label, delta, verdict))
    }

    func countTap() { tapCount += 1 }
    func countLongPress() { longPressCount += 1 }
    func setNote(_ text: String) { note = text }
    func setRestoreReport(_ text: String) { restoreReport = text }

    /// 왕복 스크롤이 끝난 시점의 델타를 통과 기준 1의 최종 수치로 기록한다.
    func captureReturnDelta() {
        sample()
        returnDelta = lastWorst
        currentDelta = lastWorst
    }

    /// 카운터만 초기화(기준 상태는 유지).
    func resetCounters() {
        offsetChangeCount = 0
        sampleCountValue = 0
        scrollEventCount = 0
        tapCount = 0
        longPressCount = 0
        sampleCount = 0
    }

    // MARK: 샘플링 루프

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(owner: self), selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// 매 프레임 실행. peak은 매 프레임 갱신하고 `@Published` 반영만 10Hz로 낮춘다.
    fileprivate func tick() {
        sample()
    }

    private func sample() {
        guard let canvas, let scrollView = governingScrollView, canvas.window != nil else {
            if governing.isAttached {
                governing = SpikeScrollSnapshot()
            }
            return
        }

        let offset = scrollView.contentOffset
        // viewport(스크롤 컨테이너)의 화면상 좌상단. 컨테이너가 통째로 움직인 양을 제거한다.
        let viewportOrigin = scrollView.convert(scrollView.bounds.origin, to: nil)
        var newSamples: [SpikeProbeSample] = []
        var worst: CGFloat = 0

        for verse in probePoints.keys.sorted() {
            guard let layoutPoint = probePoints[verse],
                  let marker = markers[verse]?.view,
                  marker.window != nil else { continue }

            // 잉크 쪽: 캔버스 content 좌표 → window 좌표 (UIKit의 변환만 사용)
            let canvasPoint = CGPoint(x: layoutPoint.x + columnOrigin.x, y: layoutPoint.y + columnOrigin.y)
            let inkWindow = canvas.convert(canvasPoint, to: nil)
            // 텍스트 쪽: 마커 뷰 중심 → window 좌표
            let markerCenter = CGPoint(x: marker.bounds.midX, y: marker.bounds.midY)
            let textWindow = marker.convert(markerCenter, to: nil)

            let inkAbsolute = CGPoint(x: inkWindow.x - viewportOrigin.x + offset.x,
                                      y: inkWindow.y - viewportOrigin.y + offset.y)
            let textAbsolute = CGPoint(x: textWindow.x - viewportOrigin.x + offset.x,
                                       y: textWindow.y - viewportOrigin.y + offset.y)
            let align = CGVector(dx: inkWindow.x - textWindow.x, dy: inkWindow.y - textWindow.y)

            guard let base = reference[verse] else {
                reference[verse] = ReferenceEntry(inkAbsolute: inkAbsolute, textAbsolute: textAbsolute, align: align)
                newSamples.append(SpikeProbeSample(verse: verse, inkResidual: 0, textResidual: 0,
                                                   alignDrift: 0, rawAlign: align))
                continue
            }

            let inkResidual = hypot(inkAbsolute.x - base.inkAbsolute.x, inkAbsolute.y - base.inkAbsolute.y)
            let textResidual = hypot(textAbsolute.x - base.textAbsolute.x, textAbsolute.y - base.textAbsolute.y)
            let alignDrift = hypot(align.dx - base.align.dx, align.dy - base.align.dy)
            let entry = SpikeProbeSample(verse: verse, inkResidual: inkResidual, textResidual: textResidual,
                                         alignDrift: alignDrift, rawAlign: align)
            worst = max(worst, entry.worst)
            newSamples.append(entry)
        }

        lastWorst = worst
        peakDeltaValue = max(peakDeltaValue, worst)
        sampleCountValue += 1
        if lastOffset.y.isNaN || abs(lastOffset.y - offset.y) > 0.001 || abs(lastOffset.x - offset.x) > 0.001 {
            offsetChangeCount += 1
            lastOffset = offset
        }

        let now = CACurrentMediaTime()
        guard now - lastPublish > 0.1 || samples.isEmpty else { return }
        lastPublish = now
        samples = newSamples
        currentDelta = worst
        peakDelta = peakDeltaValue
        sampleCount = sampleCountValue
        scrollEventCount = offsetChangeCount
        viewportOriginInWindow = viewportOrigin
        governing = snapshot(of: scrollView)
        canvasState = snapshot(of: canvas)
        gestureSummary = Self.describeGestures(of: canvas)
    }

    private static func describeGestures(of canvas: PKCanvasView) -> String {
        let all = canvas.gestureRecognizers ?? []
        let taps = all.filter { $0 is UITapGestureRecognizer && $0.isEnabled }.count
        let longs = all.filter { $0 is UILongPressGestureRecognizer && $0.isEnabled }.count
        return "draw=\(canvas.drawingGestureRecognizer.isEnabled ? "on" : "off")"
            + " pan=\(canvas.panGestureRecognizer.isEnabled ? "on" : "off")"
            + " scrollEnabled=\(canvas.isScrollEnabled)"
            + " tapGR=\(taps) longGR=\(longs) total=\(all.count)"
    }

    private func snapshot(of scrollView: UIScrollView) -> SpikeScrollSnapshot {
        SpikeScrollSnapshot(
            offset: scrollView.contentOffset,
            contentSize: scrollView.contentSize,
            contentInset: scrollView.contentInset,
            adjustedInset: scrollView.adjustedContentInset,
            zoomScale: scrollView.zoomScale,
            safeArea: scrollView.safeAreaInsets,
            isAttached: true
        )
    }

    // MARK: 프로그램 스크롤 (스크린샷만으로 판정하기 위한 경로)

    /// 정해진 만큼 내려갔다가 되돌아오는 왕복 스크롤.
    ///
    /// `setContentOffset(_:animated:)`의 애니메이션은 Core Animation이 처리하므로 model 값이
    /// 즉시 최종값으로 점프한다. 그러면 `convert(_:to:)`가 중간 프레임의 실제 위치를 보지 못한다.
    /// 그래서 **애니메이션 없이 정수 offset으로 여러 단계 이동**시키고 각 단계마다 샘플링한다.
    func runRoundTrip(
        distance: CGFloat,
        steps: Int = 24,
        stepInterval: TimeInterval = 1.0 / 60,
        completion: (() -> Void)? = nil
    ) {
        guard let scrollView = governingScrollView else {
            completion?()
            return
        }
        let start = scrollView.contentOffset.y
        let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let target = min(start + distance, maxOffset)
        note = "왕복 스크롤 실행 중 (0 → \(Int(target)) → \(Int(start)))"

        var sequence: [CGFloat] = []
        for step in 1...steps {
            sequence.append((start + (target - start) * CGFloat(step) / CGFloat(steps)).rounded())
        }
        for step in 1...steps {
            sequence.append((target + (start - target) * CGFloat(step) / CGFloat(steps)).rounded())
        }
        drive(sequence: sequence, interval: stepInterval) { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.captureReturnDelta()
            self.note = "왕복 완료 — 원점 복귀 델타 기록"
            completion?()
        }
    }

    /// 상단 bounce 영역까지 넘겼다가 되돌아온다(통과 기준 2의 rebound 구간 근사).
    func runOverscroll(completion: (() -> Void)? = nil) {
        guard let scrollView = governingScrollView else {
            completion?()
            return
        }
        let start = scrollView.contentOffset.y
        let sequence: [CGFloat] = [start - 40, start - 90, start - 140, start - 90, start - 40, start]
        note = "오버스크롤(bounce 영역) 실행 중"
        drive(sequence: sequence, interval: 1.0 / 30) { [weak self] in
            self?.captureReturnDelta()
            self?.note = "오버스크롤 완료"
            completion?()
        }
    }

    /// `async` 래퍼 — 자동 시나리오 러너에서 순서를 보장하기 위해 쓴다.
    func roundTripAsync(distance: CGFloat, steps: Int) async {
        await withCheckedContinuation { continuation in
            runRoundTrip(distance: distance, steps: steps) { continuation.resume() }
        }
    }

    func overscrollAsync() async {
        await withCheckedContinuation { continuation in
            runOverscroll { continuation.resume() }
        }
    }

    /// 임의 offset으로 즉시 이동.
    func jump(to offsetY: CGFloat) {
        governingScrollView?.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
        sample()
    }

    private func drive(sequence: [CGFloat], interval: TimeInterval, completion: @escaping () -> Void) {
        guard let scrollView = governingScrollView, !sequence.isEmpty else {
            completion()
            return
        }
        var remaining = sequence
        func step() {
            guard !remaining.isEmpty else {
                completion()
                return
            }
            let next = remaining.removeFirst()
            scrollView.setContentOffset(CGPoint(x: 0, y: next), animated: false)
            sample()
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { step() }
        }
        step()
    }

    /// 현재 offset. 재진입/장 전환 복원(통과 기준 6)에 쓴다.
    var currentOffsetY: CGFloat { governingScrollView?.contentOffset.y ?? 0 }
}

/// `CADisplayLink`가 target을 강참조하므로 프록시로 순환 참조를 끊는다.
private final class DisplayLinkProxy: NSObject {
    private weak var owner: CanvasScrollSpikeMetrics?

    init(owner: CanvasScrollSpikeMetrics) {
        self.owner = owner
    }

    @objc func tick() {
        MainActor.assumeIsolated {
            owner?.tick()
        }
    }
}
#endif
