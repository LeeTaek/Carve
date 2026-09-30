//
//  TextLayoutKeyProbeTesting.swift
//  FeatureCarveTest
//
//  Phase 0A-S2 — SwiftUI `Text.LayoutKey.Value` probe
//  단일 Canvas 설계(docs/single-canvas-design.md) §9-3 의 `textLineRanges` 실현 가능성을 확인한다.
//

import SwiftUI
import Testing
import UIKit

/// `onPreferenceChange(Text.LayoutKey.self)` 로 받은 값을 테스트로 넘기기 위한 상자.
private final class LayoutBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Text.LayoutKey.Value?

    var value: Text.LayoutKey.Value? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ newValue: Text.LayoutKey.Value) {
        lock.lock()
        stored = newValue
        lock.unlock()
    }
}

/// `VerseTextView` 와 동일하게 `Text.LayoutKey` 를 관찰하는 최소 View.
private struct LayoutProbeView: View {
    let text: String
    let width: CGFloat
    let box: LayoutBox

    var body: some View {
        Text(text)
            .font(.system(size: 17))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .onPreferenceChange(Text.LayoutKey.self) { layout in
                box.set(layout)
            }
            .frame(width: width, alignment: .leading)
    }
}

@Suite("Phase 0A-S2 — Text.LayoutKey probe")
struct TextLayoutKeyProbeTesting {

    /// `Text.LayoutKey.Value` 로부터 줄별 문자 범위를 뽑는다.
    ///
    /// - `Text.LayoutKey.Value` == `[Text.LayoutKey.AnchoredLayout]`
    /// - `AnchoredLayout.layout` == `Text.Layout` (RandomAccessCollection of `Text.Layout.Line`)
    /// - `Text.Layout.Line` 자체에는 문자 범위가 없고, 그 원소인 `Text.Layout.Run` 이
    ///   `characterIndices: [Text.Layout.CharacterIndex]` 를 노출한다.
    /// - `CharacterIndex` 는 `Strideable`(Stride == Int)이므로 기준점과의 `distance(to:)` 로
    ///   정수 offset 을 만들 수 있다.
    ///
    /// 이 함수가 **컴파일된다는 사실 자체**가 §9-3 `textLineRanges` 의 실현 가능성을 증명한다.
    static func lineCharacterRanges(from value: Text.LayoutKey.Value) -> [ClosedRange<Int>] {
        let allIndices = value.flatMap { anchored in
            anchored.layout.flatMap { line in
                line.flatMap { run in run.characterIndices }
            }
        }
        guard let reference = allIndices.min() else { return [] }

        var ranges: [ClosedRange<Int>] = []
        for anchored in value {
            for line in anchored.layout {
                let indices = line.flatMap { run in run.characterIndices }
                guard let lower = indices.min(), let upper = indices.max() else { continue }
                ranges.append(reference.distance(to: lower)...reference.distance(to: upper))
            }
        }
        return ranges
    }

    @Test("S2 Text.Layout.Run.characterIndices 로 줄별 문자 범위를 만들 수 있다 (컴파일 가능성)")
    func lineCharacterRangeExtractionCompiles() {
        // 빈 값에 대해서는 빈 배열을 돌려준다.
        #expect(Self.lineCharacterRanges(from: Text.LayoutKey.defaultValue).isEmpty)
    }

    @Test("S2 실제 렌더링에서 줄별 문자 범위가 채워진다")
    @MainActor
    func lineCharacterRangesAreProducedAtRuntime() async throws {
        let sentence = "땅이 혼돈하고 공허하며 흑암이 깊음 위에 있고 하나님의 영은 수면 위에 운행하시니라"
        let box = LayoutBox()

        let host = UIHostingController(rootView: LayoutProbeView(text: sentence, width: 180, box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        var captured: Text.LayoutKey.Value?
        for _ in 0..<60 {
            if let value = box.value, !value.isEmpty {
                captured = value
                break
            }
            try await Task.sleep(nanoseconds: 30_000_000)
            host.view.layoutIfNeeded()
        }

        let layout = try #require(captured, "Text.LayoutKey preference 를 캡처하지 못했다")
        let ranges = Self.lineCharacterRanges(from: layout)

        // 180pt 폭에서 이 문장은 여러 줄로 접힌다.
        #expect(ranges.count >= 2)
        // 줄 수와 밑줄 offset 계산에 쓰이는 line 수가 일치한다.
        let lineCount = layout.reduce(0) { $0 + $1.layout.count }
        #expect(ranges.count == lineCount)
        // 범위는 겹치지 않고 단조 증가한다.
        for (previous, next) in zip(ranges, ranges.dropFirst()) {
            #expect(previous.upperBound < next.lowerBound)
        }
        // 첫 줄은 0에서 시작하고, 마지막 줄은 문자열 길이를 넘지 않는다.
        #expect(ranges.first?.lowerBound == 0)
        let upperLimit = max(sentence.count, sentence.utf16.count)
        #expect((ranges.last?.upperBound ?? .max) < upperLimit)

        window.isHidden = true
    }
}
