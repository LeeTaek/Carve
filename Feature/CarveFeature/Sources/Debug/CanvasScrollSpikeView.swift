//
//  CanvasScrollSpikeView.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import Domain
import SwiftUI

/// 설계 §11 Phase 0A-S4 스크롤 A/B spike — **Debug 전용 격리 하네스**.
///
/// 프로덕션 경로가 아니다. `-CanvasScrollSpike` 실행 인자가 있을 때만 루트로 뜬다.
/// SwiftData·TCA·실제 사용자 Drawing과 연결되지 않는다.
///
/// ## 통과 기준 1~6을 이 하네스에서 확인하는 방법
///
/// | # | 기준 | 확인 경로 |
/// |---|---|---|
/// | 1 | 스크롤 전후 동일 content point의 stroke 오차 ≤ 1pt | `왕복` 버튼 → HUD의 `Δ / peak / return`. 세 값 모두 1pt 이하여야 통과 |
/// | 2 | 빠른 fling/rebound 후 오차 없음 | `오버스크롤`(bounce 구간 왕복) + 손가락/마우스 fling → `peak` |
/// | 3 | Split View resize 후 재필기 위치 | `폭축소` 토글(필사 컬럼 폭 변경 → 레이아웃 재계산) 또는 실제 Split View. 이후 `왕복` |
/// | 4 | 왼손잡이 레이아웃 전환 후 좌표 정합 | `왼손` 토글(컬럼이 반대편으로 이동, B는 columnX 평행이동) 이후 `왕복` |
/// | 5 | 헤더 애니메이션 / 롱프레스 / 탭 | `헤더` 토글(애니메이션) + 캔버스 탭·롱프레스 → HUD의 `tap` / `long` 카운터, 그 사이 `peak` |
/// | 6 | 재진입·장 변경 후 `contentOffset` 복원 | `재진입` / `장전환` 버튼 → HUD `restore` 줄의 요청/실제/Δ |
///
/// 7~11(Pencil hover, live stroke, `.pencilOnly` 손가락 스크롤, 메모리)은 실기기 항목이라
/// 이 하네스에서 판정하지 않는다. `펜슬전용/anyInput` 토글은 실기기에서 9·10을 볼 때 쓰라고 남겨 둔 것이다.
///
/// ## 시뮬레이터 무인 재현 (탭 없이 스크린샷만으로 판정)
///
/// ```sh
/// export DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer
/// UDID=<iPad simulator udid>
/// xcrun simctl launch $UDID kr.co.carve.leetaek \
///   -CanvasScrollSpike -CanvasScrollSpikeMode B -CanvasScrollSpikeAuto
/// sleep 25 && xcrun simctl io $UDID screenshot /tmp/spike-B.png
/// ```
///
/// | 인자 | 뜻 |
/// |---|---|
/// | `-CanvasScrollSpike` | 하네스를 루트로 띄운다(App.swift 분기) |
/// | `-CanvasScrollSpikeMode A\|B` | 시작 모드 |
/// | `-CanvasScrollSpikeAuto` | ①~⑦ 시나리오를 자동 실행하고 결과를 HUD 로그에 남긴다 |
/// | `-CanvasScrollSpikeJump <pt>` | 지정 offset으로 이동해 정지(깊은 스크롤 위치 렌더링 확인) |
/// | `-CanvasScrollSpikeLeftHanded` / `-CanvasScrollSpikeNarrow` | 시작 조건 |
/// | `-CanvasScrollSpikeAnyInput` / `-CanvasScrollSpikeNormalizeA` | 필기 정책 / A 정규화 |
public struct CanvasScrollSpikeView: View {
    @StateObject private var store = CanvasScrollSpikeStore()

    public init() { }

    public var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                canvasArea
            }
            .overlay(alignment: .bottom) { CanvasScrollSpikeHUD(store: store) }
            .onAppear {
                store.updateContainerWidth(proxy.size.width)
                store.metrics.start()
                store.startAutoRunIfNeeded()
            }
            .onDisappear { store.metrics.stop() }
            .onChange(of: proxy.size.width) { _, newValue in
                store.updateContainerWidth(newValue)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - 화면 구성

private extension CanvasScrollSpikeView {
    /// 통과 기준 5의 "헤더 애니메이션" 대상.
    var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Canvas Scroll Spike · S4")
                    .font(.headline)
                Text(store.mode.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(store.isHeaderExpanded ? "헤더 접기" : "헤더 펼치기") {
                    withAnimation(.easeInOut(duration: 0.35)) { store.isHeaderExpanded.toggle() }
                }
            }
            if store.isHeaderExpanded {
                controlRows
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    var controlRows: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Picker("mode", selection: Binding(
                    get: { store.mode },
                    set: { store.switchMode(to: $0) }
                )) {
                    ForEach(CanvasScrollSpikeMode.allCases) { mode in
                        Text("모드 \(mode.rawValue)").tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Button("장전환") { store.switchFixture() }
                Button("재진입") { store.reenter() }
                Text(store.fixture.label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 8) {
                Button("왕복 스크롤") { store.metrics.runRoundTrip(distance: 2400) }
                Button("왕복(긴)") { store.metrics.runRoundTrip(distance: 9000, steps: 40) }
                Button("오버스크롤") { store.metrics.runOverscroll() }
                Button("상단") { store.metrics.jump(to: 0) }
                Button("기준 재설정") { store.metrics.resetReference(note: "수동 기준 재설정") }
                Button("카운터 초기화") { store.metrics.resetCounters() }
                Spacer()
            }
            HStack(spacing: 12) {
                Toggle("왼손", isOn: $store.isLeftHanded).fixedSize()
                Toggle("폭축소", isOn: $store.isNarrow).fixedSize()
                Toggle("A정규화", isOn: $store.normalizeModeA).fixedSize()
                Toggle("anyInput", isOn: $store.allowFingerDrawing).fixedSize()
                Spacer()
            }
            .toggleStyle(.switch)
            .font(.caption2)
        }
    }

    @ViewBuilder
    var canvasArea: some View {
        if let bundle = store.bundle {
            ZStack {
                Color(uiColor: .systemBackground)
                switch store.mode {
                case .optionA: modeA(bundle)
                case .optionB: modeB(bundle)
                }
            }
            .id(store.instanceID)
        } else {
            Color(uiColor: .systemBackground)
        }
    }

    /// A — SwiftUI `ScrollView`가 스크롤을 담당하고, 캔버스는 content 전체 크기의 overlay다.
    func modeA(_ bundle: SpikeContentBundle) -> some View {
        ScrollView(.vertical) {
            HStack(spacing: 0) {
                if !store.isLeftHanded { Spacer(minLength: 0) }
                ZStack(alignment: .topLeading) {
                    SpikeVerseColumn(
                        layout: bundle.layout,
                        probeVerses: Set(bundle.probeVerses),
                        metrics: store.metrics
                    )
                    SpikeOverlayCanvas(
                        drawing: bundle.drawing,
                        contentKey: bundle.key,
                        allowFingerDrawing: store.allowFingerDrawing,
                        normalize: store.normalizeModeA,
                        metrics: store.metrics,
                        onAttach: { store.handleAttach() }
                    )
                    .frame(width: bundle.layout.writingWidth, height: bundle.layout.totalHeight)
                }
                .frame(width: bundle.layout.writingWidth, height: bundle.layout.totalHeight, alignment: .topLeading)
                if store.isLeftHanded { Spacer(minLength: 0) }
            }
        }
        .scrollIndicators(.visible)
    }

    /// B — `PKCanvasView`가 유일한 `UIScrollView`이고 텍스트는 그 scroll content 안에 있다.
    func modeB(_ bundle: SpikeContentBundle) -> some View {
        CanvasScrollSpikeModeB(
            layout: bundle.layout,
            drawing: bundle.drawing,
            contentKey: bundle.key,
            probeVerses: Set(bundle.probeVerses),
            metrics: store.metrics,
            isLeftHanded: store.isLeftHanded,
            allowFingerDrawing: store.allowFingerDrawing,
            onAttach: { store.handleAttach() }
        )
    }
}
#endif
