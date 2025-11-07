//
//  Item.swift
//  FocusFlip
//
//  Created by Zack Davenport on 11/7/25.
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
