//
//  ChapterLayoutDebugOverlay.swift
//  CarveFeature
//
//  Created by Claude on 9/5/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

#if DEBUG
import Domain
import SwiftUI

/// Phase 2 디버그 오버레이의 활성화 조건.
///
/// 릴리즈 빌드에는 파일 자체가 없고, Debug 빌드에서도 실행 인자가 있을 때만 그린다.
///
/// ```sh
/// xcrun simctl launch <UDID> kr.co.carve.leetaek -ChapterLayoutOverlay
/// ```
enum ChapterLayoutDebugFlags {
    static let launchArgument = "-ChapterLayoutOverlay"
    /// 실행 인자로 켠 경우. 프로세스 수명 동안 고정이다.
    static let isOverlayEnabled = ProcessInfo.processInfo.arguments.contains(launchArgument)
}

// MARK: - 콘텐츠 오버레이

/// 스크롤 콘텐츠(`VStack`) 위에 얹혀 **레이아웃이 믿는 좌표**와 **실제 행 위치**를 함께 그린다 (설계 §13 Phase 2).
///
/// 이전 두 번의 시도(§2)에서 "왜 어긋나는지 볼 수단" 이 없었던 것이 디버깅을 어렵게 했다. 이 오버레이는
/// `ChapterLayout` 의 네 가지 기하를 색으로 구분해 그리고, 실측 행 frame 을 그 위에 겹쳐 차이를 눈으로 보이게 한다.
///
/// | 색 | 대상 | 좌표 출처 |
/// |---|---|---|
/// | 파랑 실선 | `writingRect` | `ChapterLayout` (예측) |
/// | 초록 점선 | `captureRect` | `ChapterLayout` (예측) |
/// | 주황 눈금 | `underlineAnchors` | `ChapterLayout` (예측) |
/// | 빨강 점선 | 절 캔버스의 실측 frame | `onGeometryChange` (실측) |
/// | 자홍 | 마지막 편집 절의 `PKDrawing.bounds` (dirtyBounds) | 캔버스 (실측) |
///
/// 좌표계는 `ChapterLayoutHosting.coordinateSpaceName` 이며, 레이아웃 x 는 `columnOrigin.x` 만큼 평행이동해 그린다
/// (설계 §5 — 캔버스 content 좌표 = layout 좌표 + `columnOrigin`).
///
/// 거대한 `Canvas` 하나로 16,000pt 를 그리지 않고 절(`captureRect`) 단위의 작은 `Canvas` 를 쌓는다.
/// `captureRect` 는 `[0, totalHeight]` 를 빈틈·겹침 없이 분할하므로 타일처럼 맞아떨어진다.
struct ChapterLayoutDebugOverlay: View {
    let measurement: ChapterLayoutMeasurement
    /// 마지막 편집 절의 drawing bounds (content 좌표). 없으면 nil.
    let dirtyBounds: CGRect?
    /// 오버레이가 덮을 콘텐츠 폭 (`VStack` 폭).
    let contentWidth: CGFloat

    var body: some View {
        if let layout = measurement.layout {
            let columnX = measurement.columnOrigin?.x ?? 0
            ZStack(alignment: .topLeading) {
                ForEach(layout.regions, id: \.verse) { region in
                    ChapterLayoutRegionMarks(region: region)
                        .frame(width: layout.writingWidth, height: max(1, region.captureRect.height))
                        .offset(x: columnX, y: region.captureRect.minY)
                }
                ForEach(measurement.frameDeltas, id: \.verse) { delta in
                    if let frame = measurement.measuredFrames[delta.verse] {
                        Rectangle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(delta.magnitude <= 1 ? Color.red.opacity(0.55) : Color.red)
                            .frame(width: max(1, frame.width), height: max(1, frame.height))
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                if let dirtyBounds, !dirtyBounds.isNull, !dirtyBounds.isEmpty {
                    Rectangle()
                        .fill(Color.pink.opacity(0.15))
                        .overlay(Rectangle().strokeBorder(Color.pink, lineWidth: 1.5))
                        .frame(width: dirtyBounds.width, height: dirtyBounds.height)
                        .offset(x: dirtyBounds.minX, y: dirtyBounds.minY)
                }
            }
            .frame(width: contentWidth, height: layout.totalHeight, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}

/// 절 하나의 `captureRect` 크기로 그려지는 표식. 원점은 `captureRect.origin` 이다.
private struct ChapterLayoutRegionMarks: View {
    let region: VerseCanvasRegion

    var body: some View {
        Canvas { context, size in
            let capture = CGRect(origin: .zero, size: size)
            let writing = CGRect(
                x: 0,
                y: region.writingRect.minY - region.captureRect.minY,
                width: region.writingRect.width,
                height: region.writingRect.height
            )

            // captureRect — 초록 점선. 인접 절과 경계를 공유하므로 위·아래 선이 겹쳐 보이는 것이 정상이다.
            context.stroke(
                Path(capture.insetBy(dx: 0.5, dy: 0.5)),
                with: .color(.green.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            // writingRect — 파랑 실선.
            context.stroke(Path(writing.insetBy(dx: 0.5, dy: 0.5)), with: .color(.blue), lineWidth: 1)
            // underlineAnchors — 주황 눈금 (왼쪽 짧은 눈금 + 전폭 흐린 선).
            for anchor in region.underlineAnchors {
                let y = writing.minY + anchor
                var tick = Path()
                tick.move(to: CGPoint(x: writing.minX, y: y))
                tick.addLine(to: CGPoint(x: writing.minX + 14, y: y))
                context.stroke(tick, with: .color(.orange), lineWidth: 2)
                var full = Path()
                full.move(to: CGPoint(x: writing.minX + 14, y: y))
                full.addLine(to: CGPoint(x: writing.maxX, y: y))
                context.stroke(full, with: .color(.orange.opacity(0.35)), lineWidth: 1)
            }
            // 절 번호 라벨.
            let label = Text("v\(region.verse) · \(region.underlineAnchors.count)줄")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.blue)
            context.draw(label, at: CGPoint(x: writing.minX + 3, y: writing.minY + 2), anchor: .topLeading)
        }
    }
}

// MARK: - HUD

/// 화면 하단에 고정되는 측정 요약. 스크린샷 한 장으로 게이트·정확성·소요 시간을 판정할 수 있게 한다 (S4 HUD 와 같은 원칙).
struct ChapterLayoutDebugHUD: View {
    let measurement: ChapterLayoutMeasurement
    /// 마지막 편집 절 번호와 그 drawing bounds (content 좌표).
    let lastEdit: (verse: Int, bounds: CGRect)?

    private let tolerance: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            headline
            geometryLine
            deltaLine
            profileLine
            editLine
            if !measurement.missingVerses.isEmpty {
                Text("missing \(missingSummary)").foregroundStyle(.yellow)
            }
        }
        .font(.system(size: 10, weight: .regular, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.82))
        .allowsHitTesting(false)
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("LAYOUT")
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(.cyan)
            Text(chapterLabel)
            Text("\(measuredCount)/\(measurement.expectedVerseCount ?? 0)")
            Text(measurement.isReady ? "gate PASS" : "gate FAIL")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(measurement.isReady ? Color.green : Color.red)
            Text("build #\(measurement.buildCount)")
            Text("first \(durationLabel)")
            Spacer()
        }
    }

    private var geometryLine: some View {
        HStack(spacing: 10) {
            Text("W \(fmt(measurement.writingWidth))")
            Text("H \(fmt(measurement.layout?.totalHeight ?? 0))")
            Text("columnX \(measurement.columnOrigin.map { fmt($0.x) } ?? "—")")
            Text("frames \(measurement.measuredFrames.count)")
            Text("sig \(measurement.layout.map { String($0.signature.prefix(14)) } ?? "—")")
        }
    }

    private var deltaLine: some View {
        let worst = measurement.worstFrameDelta
        let magnitude = worst?.magnitude ?? 0
        return HStack(spacing: 10) {
            Text("Δ max \(fmt(magnitude))")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(worst == nil ? Color.gray : (magnitude <= tolerance ? Color.green : Color.red))
            if let worst {
                Text("worst v\(worst.verse)  top \(signed(worst.topDelta))  height \(signed(worst.heightDelta))")
            } else {
                Text("(실측 frame 대기)").foregroundStyle(.gray)
            }
            Text("tol \(fmt(tolerance))pt").foregroundStyle(.gray)
        }
    }

    /// 절별 Δ 프로파일 — 누적 기울기와 height delta 의 분포를 한 줄로 본다 (D9 진단).
    ///
    /// `top` 이 절 번호에 선형으로 늘고 `h` 의 min == max 면 **절당 상수 오차의 누적**이다.
    /// `h` 가 절마다 다르면 텍스트 높이 예측 자체가 흔들리는 것이므로 원인이 다르다.
    private var profileLine: some View {
        let deltas = measurement.frameDeltas.sorted { $0.verse < $1.verse }
        return Group {
            if deltas.count >= 2 {
                let heights = deltas.map(\.heightDelta)
                let minHeight = heights.min() ?? 0
                let maxHeight = heights.max() ?? 0
                // 첫 절·1/4·1/2·마지막 지점의 top delta 를 뽑는다.
                let picks = [0, deltas.count / 4, deltas.count / 2, deltas.count - 1]
                let samples = Array(Set(picks)).sorted().map { deltas[$0] }
                let slope = deltas.count > 1
                    ? (deltas[deltas.count - 1].topDelta - deltas[0].topDelta) / CGFloat(deltas.count - 1)
                    : 0
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 10) {
                        Text("h[min \(signed(minHeight)) max \(signed(maxHeight))]")
                            .foregroundStyle(minHeight == maxHeight ? Color.orange : Color.yellow)
                        Text("slope \(String(format: "%+.3f", slope))/절")
                            .foregroundStyle(.orange)
                    }
                    Text("top " + samples.map { "v\($0.verse) \(signed($0.topDelta))" }.joined(separator: " · "))
                }
            } else {
                Text("prof —").foregroundStyle(.gray)
            }
        }
    }

    private var editLine: some View {
        Group {
            if let lastEdit {
                let rect = lastEdit.bounds
                Text("dirty v\(lastEdit.verse)  (\(fmt(rect.minX)), \(fmt(rect.minY)), \(fmt(rect.width)) × \(fmt(rect.height)))")
                    .foregroundStyle(.pink)
            } else {
                Text("dirty —").foregroundStyle(.gray)
            }
        }
    }

    private var chapterLabel: String {
        guard let chapter = measurement.chapter else { return "—" }
        return "\(chapter.title.koreanTitle()) \(chapter.chapter)장"
    }

    private var measuredCount: Int {
        measurement.textMeasurements.count
    }

    private var durationLabel: String {
        guard let duration = measurement.firstBuildDuration else { return "—" }
        let millis = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        return String(format: "%.0f ms", millis)
    }

    private var missingSummary: String {
        let missing = measurement.missingVerses
        let head = missing.prefix(12).map(String.init).joined(separator: ",")
        return missing.count > 12 ? "\(head)… (\(missing.count))" : head
    }

    private func fmt(_ value: CGFloat) -> String { String(format: "%.2f", value) }
    private func signed(_ value: CGFloat) -> String { String(format: "%+.2f", value) }
}
#endif
