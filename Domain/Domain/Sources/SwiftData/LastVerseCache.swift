//
//  LastVerseCache.swift
//  Domain
//
//  Created by 이택성 on 1/24/25.
//  Copyright © 2025 leetaek. All rights reserved.
//

import Foundation

public class LastVerseCache {
    static let shared = LastVerseCache()
    private var lastVerse: [BibleTitle: [Int]] = [:]
    
}
