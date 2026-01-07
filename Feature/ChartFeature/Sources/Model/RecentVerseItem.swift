//
//  RecentVerseItem.swift
//  ChartFeature
//
//  Created by 이택성 on 1/7/26.
//  Copyright © 2026 leetaek. All rights reserved.
//

import Foundation
import Domain

public struct RecentVerseItem: Equatable, Identifiable, Sendable {
  public var id: String {
    "\(verse.title.title.rawValue)|\(verse.title.chapter)|\(verse.verse)|\(updatedAt.timeIntervalSince1970)"
  }

  public let verse: BibleVerse
  public let updatedAt: Date
  public let drawingID: String?

  public init(verse: BibleVerse, updatedAt: Date, drawingID: String? = nil) {
    self.verse = verse
    self.updatedAt = updatedAt
    self.drawingID = drawingID
  }

  public var message: String {
    let book = verse.title.title.koreanTitle()
    return "\(book) \(verse.title.chapter)장 \(verse.verse)절"
  }
}
