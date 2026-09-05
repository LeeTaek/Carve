//
//  CanvasScrollSpikeStore.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import Domain
import PencilKit
import SwiftUI

/// 한 번 만들어 두고 A/B가 공유하는 콘텐츠 묶음.
struct SpikeContentBundle: Equatable {
    let layout: ChapterLayout
    let drawing: PKDrawing
    /// 콘텐츠 동일성 키. 값이 같으면 A와 B가 **완전히 같은** 레이아웃·Drawing을 쓴다.
    let key: String
    let probeVerses: [Int]

    static func == (lhs: SpikeContentBundle, rhs: SpikeContentBundle) -> Bool { lhs.key == rhs.key }
}

/// 실행 인자로 받는 초기 조건.
///
/// 시뮬레이터에서 탭을 주입할 수단이 없어도 `xcrun simctl launch` 인자만으로
/// A/B·왼손·폭축소 조건과 자동 시나리오를 재현할 수 있게 한다.
///
/// ```
/// xcrun simctl launch <udid> kr.co.carve.leetaek \
///   -CanvasScrollSpike -CanvasScrollSpikeMode A -CanvasScrollSpikeAuto
/// ```
struct SpikeLaunchOptions {
    var mode: CanvasScrollSpikeMode = .optionB
    var isLeftHanded = false
    var isNarrow = false
    var allowFingerDrawing = false
    var normalizeModeA = false
    var autoRun = false
    /// 지정하면 화면이 뜬 뒤 그 offset으로 이동해 멈춘다. 깊은 스크롤 위치의 렌더링 확인용.
    var jumpOffset: CGFloat?

    static func parse(_ arguments: [String]) -> SpikeLaunchOptions {
        var options = SpikeLaunchOptions()
        if let index = arguments.firstIndex(of: "-CanvasScrollSpikeJump"),
           index + 1 < arguments.count,
           let value = Double(arguments[index + 1]) {
            options.jumpOffset = CGFloat(value)
        }
        if let index = arguments.firstIndex(of: "-CanvasScrollSpikeMode"),
           index + 1 < arguments.count,
           let mode = CanvasScrollSpikeMode(rawValue: arguments[index + 1].uppercased()) {
            options.mode = mode
        }
        options.isLeftHanded = arguments.contains("-CanvasScrollSpikeLeftHanded")
        options.isNarrow = arguments.contains("-CanvasScrollSpikeNarrow")
        options.allowFingerDrawing = arguments.contains("-CanvasScrollSpikeAnyInput")
        options.normalizeModeA = arguments.contains("-CanvasScrollSpikeNormalizeA")
        options.autoRun = arguments.contains("-CanvasScrollSpikeAuto")
        return options
    }
}

/// 스파이크 하네스의 상태 보관소.
///
/// SwiftData·TCA·실제 Drawing과 연결되지 않는다. 전부 메모리 안에서만 산다(설계 §11 실험 범위).
@MainActor
final class CanvasScrollSpikeStore: ObservableObject {
    /// 현재 호스팅 구조. 전환은 `switchMode(to:)`로만 한다(offset 보관/복원 때문).
    @Published private(set) var mode: CanvasScrollSpikeMode = .optionB
    @Published private(set) var fixture: CanvasScrollSpikeFixture = .psalm119
    /// 통과 기준 4 — 왼손잡이 레이아웃 전환.
    @Published var isLeftHanded = false { didSet { rebuild() } }
    /// 통과 기준 3 — Split View resize 근사(필사 컬럼 폭 축소).
    @Published var isNarrow = false { didSet { rebuild() } }
    /// A 모드에서 `StableCanvasView` 수준의 offset/inset/zoom 정규화를 매 레이아웃 적용할지.
    @Published var normalizeModeA = false
    /// `.anyInput`(손가락 필기 허용) ↔ `.pencilOnly`.
    @Published var allowFingerDrawing = false
    /// 통과 기준 5 — 헤더 애니메이션.
    @Published var isHeaderExpanded = true
    /// 통과 기준 6 — 재진입(뷰 트리 재생성) 트리거.
    @Published private(set) var instanceID = UUID()
    @Published private(set) var bundle: SpikeContentBundle?

    let metrics = CanvasScrollSpikeMetrics()

    private var containerWidth: CGFloat = 0
    private var cache: [String: SpikeContentBundle] = [:]
    private var savedOffsets: [CanvasScrollSpikeFixture: CGFloat] = [:]
    private var pendingRestore: CGFloat?
    private var attachCompleted = false
    private var didStartAutoRun = false
    private let options: SpikeLaunchOptions

    init(options: SpikeLaunchOptions = .parse(ProcessInfo.processInfo.arguments)) {
        self.options = options
        mode = options.mode
        isLeftHanded = options.isLeftHanded
        isNarrow = options.isNarrow
        allowFingerDrawing = options.allowFingerDrawing
        normalizeModeA = options.normalizeModeA
    }

    // MARK: 콘텐츠

    /// 필사 컬럼 폭. 캔버스 content 폭과 같다.
    var writingWidth: CGFloat {
        let narrowing: CGFloat = isNarrow ? 220 : 0
        return max(240, containerWidth - CanvasScrollSpikeContent.columnGutter - narrowing)
    }

    func updateContainerWidth(_ width: CGFloat) {
        guard width > 0, abs(width - containerWidth) > 0.5 else { return }
        containerWidth = width
        rebuild()
    }

    private func rebuild() {
        guard containerWidth > 0 else { return }
        let key = "\(fixture.rawValue)|w\(Int(writingWidth.rounded()))|\(isLeftHanded ? "L" : "R")"
        let made: SpikeContentBundle
        if let cached = cache[key] {
            made = cached
        } else {
            let layout = CanvasScrollSpikeContent.makeLayout(
                fixture: fixture,
                writingWidth: writingWidth,
                isLeftHanded: isLeftHanded
            )
            let probes = CanvasScrollSpikeContent.probeVerses(fixture: fixture)
            let drawing = CanvasScrollSpikeContent.makeDrawing(layout: layout, probeVerses: probes)
            made = SpikeContentBundle(layout: layout, drawing: drawing, key: key, probeVerses: probes)
            cache[key] = made
        }
        bundle = made
        var points: [Int: CGPoint] = [:]
        for verse in made.probeVerses {
            guard let region = made.layout.region(verse: verse) else { continue }
            points[verse] = CanvasScrollSpikeContent.probePoint(region: region)
        }
        metrics.setProbePoints(points)
    }

    // MARK: 통과 기준 6 — offset 저장 / 복원

    /// 모드·장·재진입으로 뷰가 교체되기 직전에 현재 offset을 보관한다.
    private func saveOffset() {
        savedOffsets[fixture] = metrics.currentOffsetY
    }

    /// 재진입 — 뷰 트리를 파기하고 다시 만든다.
    func reenter() {
        saveOffset()
        scheduleRestore(to: savedOffsets[fixture] ?? 0)
    }

    /// 장 전환.
    func switchFixture() {
        saveOffset()
        let next: CanvasScrollSpikeFixture = fixture == .psalm119 ? .genesis1 : .psalm119
        fixture = next
        rebuild()
        scheduleRestore(to: savedOffsets[next] ?? 0)
    }

    /// 모드 전환.
    func switchMode(to newMode: CanvasScrollSpikeMode) {
        guard newMode != mode else { return }
        saveOffset()
        mode = newMode
        scheduleRestore(to: savedOffsets[fixture] ?? 0)
    }

    private func scheduleRestore(to target: CGFloat) {
        pendingRestore = target
        attachCompleted = false
        instanceID = UUID()
    }

    /// 캔버스가 window에 붙은 뒤 호출된다. 보관해 둔 offset을 복원하고 결과를 HUD에 남긴다.
    func handleAttach() {
        guard let target = pendingRestore else {
            metrics.setRestoreReport("복원 요청 없음")
            finishAttachWait()
            return
        }
        pendingRestore = nil
        // contentSize가 확정된 뒤에 적용해야 clamp되지 않는다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.metrics.jump(to: target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let actual = self.metrics.currentOffsetY
                let delta = abs(actual - target)
                self.metrics.setRestoreReport(
                    String(format: "요청 %.1f → 실제 %.1f (Δ%.2f)", target, actual, delta)
                )
                self.metrics.resetReference(note: "복원 후 기준 재설정")
                self.restoreDelta = delta
                self.finishAttachWait()
            }
        }
    }

    private(set) var restoreDelta: CGFloat = 0

    private func finishAttachWait() {
        attachCompleted = true
    }

    /// 재부착(복원 포함)이 끝날 때까지 기다린다. 타임아웃을 두어 시나리오가 멈추지 않게 한다.
    /// `attachCompleted`는 복원을 예약하는 쪽(`reenter` 등)에서 미리 내려 둔다.
    private func waitForAttach(timeout: TimeInterval = 4) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !attachCompleted, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: 자동 시나리오 (탭 주입 없이 스크린샷만으로 판정하기 위한 경로)

    /// `-CanvasScrollSpikeAuto` / `-CanvasScrollSpikeJump`가 있으면 화면이 뜬 뒤 한 번 실행한다.
    func startAutoRunIfNeeded() {
        guard !didStartAutoRun else { return }
        didStartAutoRun = true
        if let jumpOffset = options.jumpOffset {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                metrics.resetPeak()
                metrics.jump(to: jumpOffset)
                try? await Task.sleep(nanoseconds: 800_000_000)
                metrics.appendResult(String(format: "JUMP %.0fpt 유지", jumpOffset), delta: metrics.peakDelta)
                metrics.setNote("JUMP 완료 — 이 위치에서 텍스트/잉크 렌더링 확인")
            }
            return
        }
        guard options.autoRun else { return }
        Task { await runAutoScenario() }
    }

    private func runAutoScenario() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        metrics.appendResult("AUTO 시작 · 모드 \(mode.rawValue) · \(fixture.label)", delta: nil)

        await stage("① 왕복 스크롤 9000pt") { await self.metrics.roundTripAsync(distance: 9000, steps: 40) }
        await stage("② 오버스크롤(bounce)") { await self.metrics.overscrollAsync() }
        await stage("③ 헤더 애니메이션 중 스크롤") {
            withAnimation(.easeInOut(duration: 0.4)) { self.isHeaderExpanded = false }
            await self.metrics.roundTripAsync(distance: 1800, steps: 20)
            withAnimation(.easeInOut(duration: 0.4)) { self.isHeaderExpanded = true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        await stage("④ 왼손 레이아웃 전환 후 왕복") {
            self.isLeftHanded.toggle()
            try? await Task.sleep(nanoseconds: 700_000_000)
            await self.metrics.roundTripAsync(distance: 3000, steps: 24)
        }
        await stage("⑤ 폭축소(resize) 후 왕복") {
            self.isNarrow = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            await self.metrics.roundTripAsync(distance: 3000, steps: 24)
        }

        // ⑥ 재진입 / 장 전환 후 contentOffset 복원
        metrics.jump(to: 4200)
        try? await Task.sleep(nanoseconds: 300_000_000)
        reenter()
        await waitForAttach()
        metrics.appendResult("⑥ 재진입 복원 · \(metrics.restoreReport)", delta: restoreDelta)

        switchFixture()
        await waitForAttach()
        try? await Task.sleep(nanoseconds: 400_000_000)
        switchFixture()
        await waitForAttach()
        metrics.appendResult("⑦ 장 전환 왕복 복원 · \(metrics.restoreReport)", delta: restoreDelta)

        metrics.setNote("AUTO 완료 — 결과 로그 참조")
    }

    private func stage(_ label: String, _ body: () async -> Void) async {
        metrics.resetPeak()
        metrics.setNote(label + " 실행 중")
        await body()
        try? await Task.sleep(nanoseconds: 300_000_000)
        metrics.appendResult(label, delta: metrics.peakDelta)
    }
}
#endif
