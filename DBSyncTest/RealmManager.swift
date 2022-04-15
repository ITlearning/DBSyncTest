//
//  RealmManager.swift
//  DBSyncTest
//
//  Created by 인병윤 on 2022/04/13.
//

import Foundation
import RealmSwift
import Photos

public class RealmManager {
    let realm = try! Realm()

    static let shared = RealmManager()

    func readAllObject() -> Results<DataBaseModel>? {
        return realm.objects(DataBaseModel.self)
    }

    
}
