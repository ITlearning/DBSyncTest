//
//  DataBaseModel.swift
//  DBSyncTest
//
//  Created by 인병윤 on 2022/04/13.
//

import Foundation
import RealmSwift

class DataBaseModel: Object {
    // Element
    @Persisted var id: String                // 이미지 고유 ID
    @Persisted var path: String?             // 이미지 파일 경로
    // Optional
    @Persisted var createdAt: String?        // 파일 생성일시(ISO-8601)
    @Persisted var takenAt: String?          // 촬영 일시(ISO-8601)
    @Persisted var lat: Double?              // 위도
    @Persisted var lng: Double?              // 경도
    @Persisted var pid: String?              // 아이폰 UID
    @Persisted var isUpload: Int             // 업로드 여부
    @Persisted var localUpdatedAt: String    // 테이블에 업데이트 된 일시
    @Persisted var editedAt: String?         // 사진 수정일시(ISO-8601)
    @Persisted var modificationDate: String? // 마지막 수정일시(ISO-8601)
}
