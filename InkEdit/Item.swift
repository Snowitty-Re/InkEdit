//
//  Item.swift
//  InkEdit
//
//  Created by Snowitty on 2026/8/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
