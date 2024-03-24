//
//  RealmInterface.swift
//  DomainRealm
//
//  Created by 이택성 on 1/29/24.
//  Copyright © 2024 leetaek. All rights reserved.
//

import Foundation

public protocol RealmInterface {
    func setSubscriptions() async throws
    func clearSubscriptions() async throws
//    func updateSubscription(lines: RealmSwift.List<LineDTO>) async throws
}
