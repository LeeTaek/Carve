//
//  FeedbackVO.swift
//  Domain
//
//  Created by 이택성 on 7/25/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

public struct FeedbackVO: Equatable, Hashable {
    public var feedbackType: String
    public var email: String
    public var title: String
    public var body: String
    public var attachment: [Data]?
    public let feedbackAddress: String = Bundle.main.object(forInfoDictionaryKey: "FeedbackAddress") as! String
    public var deviceInfo: String
    
    public static var initialState = Self(feedbackType: "",
                                          email: "",
                                          title: "",
                                          body: "",
                                          deviceInfo: "")
    public init(feedbackType: String,
                email: String,
                title: String,
                body: String,
                attachment: [Data]? = nil,
                deviceInfo: String
    ) {
        self.feedbackType = feedbackType
        self.email = email
        self.title = title
        self.body = body
        self.attachment = attachment
        self.deviceInfo = deviceInfo
    }
}

