//
//  QueueModel.swift
//  DBSyncTest
//
//  Created by 인병윤 on 2022/04/13.
//

import Foundation
import Photos

enum QueueType {
    case add
    case remove
    case edit
}

struct QueueModel {
    var dbModel: PHAsset
    var queueType: QueueType
}
