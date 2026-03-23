//
//  PerformanceLog.swift
//  FeatureCarve
//
//  Created by Codex on 1/28/26.
//

import os

enum PerformanceLog {
    static let log = OSLog(subsystem: "com.carve", category: "performance")

    @inline(__always)
    static func begin(_ name: StaticString) -> OSSignpostID {
#if DEBUG
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
#else
        return OSSignpostID(log: log)
#endif
    }

    @inline(__always)
    static func end(_ name: StaticString, _ id: OSSignpostID) {
#if DEBUG
        os_signpost(.end, log: log, name: name, signpostID: id)
#endif
    }

    @inline(__always)
    static func event(_ name: StaticString) {
#if DEBUG
        os_signpost(.event, log: log, name: name)
#endif
    }
}
