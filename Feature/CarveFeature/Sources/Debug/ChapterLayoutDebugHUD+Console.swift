#if DEBUG
import Domain
import Foundation

extension ChapterLayoutDebugHUD {
    /// HUD와 동일한 측정·합성 입력을 문자열로 만든다. 시각적 렌더 완료를 보증하지 않는다.
    /// 시간값을 넣지 않아 동일한 표시 값에는 onChange가 재발생하지 않는다.
    var consoleSnapshot: String {
        let chapter = measurement.chapter.map { "\($0.title.koreanTitle()) \($0.chapter)장" } ?? "—"
        let duration = measurement.firstBuildDuration.map {
            Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15
        }
        var fields = [
            "chapter=\(chapter)",
            "mode=\(compose == nil ? "N-Canvas" : "SingleCanvas")",
            "gate=\(measurement.isReady ? "PASS" : "FAIL")",
            "measured=\(measurement.textMeasurements.count)/\(measurement.expectedVerseCount ?? 0)",
            "build=\(measurement.buildCount) firstMs=\(duration.map { String(format: "%.0f", $0) } ?? "—")",
            "W=\(number(measurement.writingWidth)) H=\(number(measurement.layout?.totalHeight ?? 0))",
            "columnOrigin=\(String(describing: measurement.columnOrigin)) frames=\(measurement.measuredFrames.count)",
            "sig=\(measurement.layout?.signature ?? "—") missing=\(measurement.missingVerses)",
            "tol=\(number(LayoutDeltaVerdict.tolerance)) slack=\(measurement.hasReflowSlack)"
        ]
        if let worst = measurement.worstFrameDelta {
            fields.append("deltaMax=\(number(worst.magnitude)) worst=v\(worst.verse) top=\(number(worst.topDelta)) height=\(number(worst.heightDelta))")
        } else {
            fields.append("deltaMax=unmeasured")
        }
        let deltas = measurement.frameDeltas.sorted { $0.verse < $1.verse }
        if let first = deltas.first, let last = deltas.last, deltas.count >= 2 {
            let heights = deltas.map(\.heightDelta)
            let slope = (last.topDelta - first.topDelta) / CGFloat(deltas.count - 1)
            let indices = Set([0, deltas.count / 4, deltas.count / 2, deltas.count - 1]).sorted()
            let samples = indices.map { "v\(deltas[$0].verse):\(number(deltas[$0].topDelta))" }.joined(separator: ",")
            fields.append("heightMin=\(number(heights.min() ?? 0)) heightMax=\(number(heights.max() ?? 0)) slope=\(String(format: "%+.3f", slope)) top=[\(samples)]")
        } else {
            fields.append("profile=unmeasured")
        }
        if let safetyNet {
            fields.append("guard=\(safetyNet.blocksInput ? "BLOCKED" : "OPEN") verse=\(safetyNet.verse) delta=\(number(safetyNet.magnitude)) limit=\(number(safetyNet.lineSpace))")
        } else {
            fields.append("guard=unavailable")
        }
        if let compose {
            let synced = compose.renderedSignature == measurement.layout?.signature
                && compose.renderedColumnOrigin == compose.columnOrigin
            fields += [
                "compose=\(synced ? "SYNC" : "STALE") csig=\(compose.renderedSignature ?? "—") rev=\(compose.renderedRevision)",
                "org=\(compose.renderedColumnOrigin)->\(compose.columnOrigin)",
                "reload=\(compose.isReloading) reloadWhenSettled=\(compose.reloadWhenSettled) editing=\(compose.isEditing) pendingLayout=\(compose.hasPendingLayout)",
                "mismatch=\(compose.mismatchVerses) legacy=\(compose.legacyVerses) undecodable=\(compose.undecodableVerses)",
                "legacyInk=\(String(describing: compose.legacyInkBounds))"
            ]
        } else {
            fields.append("compose=unavailable")
        }
        fields.append(lastEdit.map { "dirty=v\($0.verse):\($0.bounds)" } ?? "dirty=none")
        return fields.joined(separator: " | ")
    }

    private func number(_ value: CGFloat) -> String { String(format: "%.2f", value) }
}
#endif
