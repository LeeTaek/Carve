//
//  CanvasScrollSpikeHUD.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import Domain
import SwiftUI
import UIKit

/// 하네스가 **스스로 계산한 수치**를 항상 화면에 띄우는 HUD.
///
/// 시뮬레이터 스크린샷 한 장으로 통과/실패를 판정할 수 있어야 하므로
/// 1pt를 넘는 값은 즉시 색으로 구분된다(초록 = 통과, 빨강 = 초과).
struct CanvasScrollSpikeHUD: View {
    @ObservedObject var store: CanvasScrollSpikeStore
    @ObservedObject private var metrics: CanvasScrollSpikeMetrics

    init(store: CanvasScrollSpikeStore) {
        self.store = store
        self.metrics = store.metrics
    }

    private var tolerance: CGFloat { CanvasScrollSpikeMetrics.tolerance }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headline
            probeLines
            Divider().overlay(Color.white.opacity(0.25))
            geometryLines
            statusLines
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.82))
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("MODE \(store.mode.rawValue)")
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundStyle(store.mode == .optionB ? Color.cyan : Color.orange)
            value(label: "Δ", metric: metrics.currentDelta)
            value(label: "peak", metric: metrics.peakDelta)
            if let returnDelta = metrics.returnDelta {
                value(label: "return", metric: returnDelta)
            } else {
                Text("return —").foregroundStyle(.gray)
            }
            Text("tol \(String(format: "%.1f", tolerance))pt").foregroundStyle(.gray)
            Spacer()
        }
    }

    private func value(label: String, metric: CGFloat) -> some View {
        let pass = metric <= tolerance
        return Text("\(label) \(String(format: "%.3f", metric))")
            .font(.system(size: 20, weight: .bold, design: .monospaced))
            .foregroundStyle(pass ? Color.green : Color.red)
    }

    private var probeLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            if metrics.samples.isEmpty {
                Text("probe  (측정 대기 — 마커가 아직 window에 없음)").foregroundStyle(.yellow)
            }
            ForEach(metrics.samples) { sample in
                HStack(spacing: 8) {
                    Text("probe v\(sample.verse)".padding(to: 11))
                    Text("ink \(fmt(sample.inkResidual))")
                        .foregroundStyle(sample.inkResidual <= tolerance ? Color.green : Color.red)
                    Text("txt \(fmt(sample.textResidual))")
                        .foregroundStyle(sample.textResidual <= tolerance ? Color.green : Color.red)
                    Text("algn \(fmt(sample.alignDrift))")
                        .foregroundStyle(sample.alignDrift <= tolerance ? Color.green : Color.red)
                    Text("rawAlign(\(fmt(sample.rawAlign.dx)), \(fmt(sample.rawAlign.dy)))")
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    private var geometryLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("scroll " + describe(metrics.governing))
            Text("canvas " + describe(metrics.canvasState))
            Text("viewportOrigin(\(fmt(metrics.viewportOriginInWindow.x)), \(fmt(metrics.viewportOriginInWindow.y)))"
                 + "   safeArea \(inset(metrics.governing.safeArea))"
                 + "   events \(metrics.scrollEventCount)   samples \(metrics.sampleCount)")
        }
    }

    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let layout = store.bundle?.layout {
                let gate = layout.satisfiesCompositionGate(expectedVerseCount: layout.regions.count)
                Text("layout \(layout.regions.count)절  W \(fmt(layout.writingWidth))  H \(fmt(layout.totalHeight))  gate \(gate ? "PASS" : "FAIL")  \(layout.signature.prefix(14))")
            }
            Text("tap \(metrics.tapCount)  long \(metrics.longPressCount)"
                 + "  policy \(store.allowFingerDrawing ? "anyInput" : "pencilOnly")"
                 + "  header \(store.isHeaderExpanded ? "펼침" : "접힘")"
                 + "  왼손 \(onOff(store.isLeftHanded))  폭축소 \(onOff(store.isNarrow))"
                 + "  A정규화 \(onOff(store.normalizeModeA))")
            Text("gestures \(metrics.gestureSummary)")
            Text("restore \(metrics.restoreReport)")
            Text("note \(metrics.note)").foregroundStyle(.yellow)
            ForEach(Array(metrics.results.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .foregroundStyle(line.hasSuffix("FAIL") ? Color.red : Color.cyan)
            }
        }
    }

    private func describe(_ snapshot: SpikeScrollSnapshot) -> String {
        guard snapshot.isAttached else { return "(미연결)" }
        return "off(\(fmt(snapshot.offset.x)), \(fmt(snapshot.offset.y)))  "
            + "size \(fmt(snapshot.contentSize.width))x\(fmt(snapshot.contentSize.height))  "
            + "inset\(inset(snapshot.contentInset))  adj\(inset(snapshot.adjustedInset))  "
            + "zoom \(fmt(snapshot.zoomScale))"
    }

    private func inset(_ value: UIEdgeInsets) -> String {
        "(\(fmt(value.top)),\(fmt(value.left)),\(fmt(value.bottom)),\(fmt(value.right)))"
    }

    private func onOff(_ flag: Bool) -> String { flag ? "ON" : "off" }

    private func fmt(_ value: CGFloat) -> String { String(format: "%.2f", value) }
}

private extension String {
    /// HUD 정렬용 고정폭 패딩.
    func padding(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
#endif
