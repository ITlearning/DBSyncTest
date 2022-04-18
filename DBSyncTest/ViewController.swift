//
//  ViewController.swift
//  DBSyncTest
//
//  Created by 인병윤 on 2022/04/13.
//

import UIKit
import Photos
import PhotosUI
import RealmSwift
import Toast

class ViewController: UIViewController {

    @IBOutlet weak var locationInfoLabel: UILabel!
    @IBOutlet weak var reBuildButton: UIButton!
    @IBOutlet weak var currentUpdateLabel: UILabel!
    @IBOutlet weak var libraryPhotoCntLabel: UILabel!
    @IBOutlet weak var syncEndDateLabel: UILabel!
    @IBOutlet weak var syncStartDateLabel: UILabel!
    @IBOutlet weak var circleView: UIActivityIndicatorView!
    @IBOutlet weak var appDBCntLabel: UILabel!
    @IBOutlet weak var syncMinus: UILabel!
    
    private var fetchResult = PHFetchResult<PHAsset>()
    var dbCnt = 0
    let dispatchQueue = DispatchQueue(label: "serial")
    var startDate = Date()
    var endDate = Date()
    var queue: Queue<QueueModel> = Queue<QueueModel>()
    @IBOutlet weak var syncButton: UIButton!
    var addAssets = [PHAsset]()
    var deleteAssets = [PHAsset]()
    var changeAssets = [PHAsset]()
    var notificationToken: NotificationToken?
    var count = 0
    var end = 4000

    override func viewDidLoad() {
        super.viewDidLoad()
        PHPhotoLibrary.shared().register(self)
        // 버튼 세팅
        configureButton()
        // 데이터 전체 세팅
        setAllData()
    }

    func configureButton() {
        syncButton.addTarget(self, action: #selector(syncAction), for: .touchUpInside)
        reBuildButton.addTarget(self, action: #selector(reBuildAction), for: .touchUpInside)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

}


// MARK: - objc Functions
extension ViewController {
    
    @objc
    func reBuildAction() {
        setAllData()
    }
    
    @objc
    func syncAction() {
        removeAll()
    }
    
    @objc
    func startAction() {
        DispatchQueue.main.async {
            self.circleView.startAnimating()
            let startDate = Date()
            let date = Date().dateToStringNormal(date: Date())
            self.startDate = startDate
            self.syncStartDateLabel.text = "동기화 시작 시간 : \(date ?? "")"
        }
    }

    @objc
    func delayAction() {
        var queueCnt = self.queue.count
        var locationCnt = 0
        var saveCnt = 0
        let realm = try! Realm()
        DispatchQueue.global().sync {
            autoreleasepool {
                while saveCnt < queueCnt {
                    realm.beginWrite()
                    for idx in 0..<200 {
                        if !self.queue.isEmpty() {
                            guard let item = self.queue.dequeue() else { return }
                            if let _ = item.dbModel.location {
                                locationCnt += 1
                            }
                            realm.create(DataBaseModel.self, value: writeRealm(item: item.dbModel))
                        } else {
                            break
                        }
                    }
                    saveCnt += 200
                    print("\(saveCnt) 개 저장시도")
                    try! realm.commitWrite()
                }
                
                
            }
            DispatchQueue.main.async {
                self.locationInfoLabel.text = "위치 정보가 있는 사진 개수 : \(locationCnt) / \(queueCnt)"
            }
            // 저장된 개수보다 로드한 이미지의 개수가 더 적을 경우
            if UserDefaults.standard.integer(forKey: "DBcount") > self.fetchResult.count {
                // 4. 지우기 로직
                self.deleteLogic()
                UserDefaults.standard.set(self.fetchResult.count, forKey: "DBcount")
            }
            
            // 5. 수정 로직
            self.editLogic()
        }
        
        DispatchQueue.main.async {
            self.circleView.stopAnimating()
            let endDate = Date()
            let date = Date().dateToStringNormal(date: Date())
            self.endDate = endDate
            self.syncEndDateLabel.text = "동기화 완료 시간 : \(date)"
            let remainTime = Int(self.endDate.timeIntervalSince(self.startDate))
            self.syncMinus.text = "동기화까지 걸린 시간: \(remainTime.minute) 분 \(remainTime.seconds)초"
            self.currentUpdateLabel.text = "가장최근 동기화 시간: \(Date().dateToStringNormal(date: Date()))"
            do {
                let realm = try Realm()
                let object = realm.objects(DataBaseModel.self)
                self.dbCnt = object.count
                self.appDBCntLabel.text = "동기화된 DB 개수 : \(self.dbCnt)"
            } catch {
                print("카운트 오류")
            }
            
        }
            
    }
}

// MARK: - ViewController Functions
extension ViewController {
    
    func setAllData() {
        
        DispatchQueue.main.async {
            self.currentUpdateLabel.text = "가장최근 동기화 시간:"
            self.libraryPhotoCntLabel.text = "갤러리에 들어가있는 사진 개수:"
            self.appDBCntLabel.text = "동기화된 사진 개수: 0"
            self.syncEndDateLabel.text = "동기화 완료 시간: "
        }
        
        // 1. 가지고 있는 모든 사진 가져오기
        self.loadAllPhoto()

        // 2. 가져온 사진 개수 리스트
        DispatchQueue.main.async {
            self.libraryPhotoCntLabel.text = "갤러리에 들어가있는 사진 개수 \(self.fetchResult.count) 개"
        }

        // 3. 가져온 사진 큐에 넣기
        DispatchQueue.global().sync {
            self.fetchResult.enumerateObjects { asset, _, _ in
                let realm = try! Realm()
                if let _ = realm.objects(DataBaseModel.self).filter("id == '\(asset.localIdentifier)'").first {
                } else {
                    let item = QueueModel(dbModel: asset, queueType: .add)
                    self.queue.enqueue(element: item)
                }

                //self.count += 1
            }
        }

        // 6. 큐에 들어간 사진들 돌리기
        perform(#selector(startAction), with: nil, afterDelay: 0.5)
        perform(#selector(delayAction), with: nil, afterDelay: 0.8)
    }
    
    func add(object: DataBaseModel) {
        DispatchQueue.global().sync {
            do {
                let realm = try Realm()
                try realm.write {
                    //print("🌟 \(object.id) 사진 저장 완료!")
                    realm.add(object)
                    DispatchQueue.main.async {
                        self.dbCnt += 1
                        self.appDBCntLabel.text = "동기화된 DB 개수 : \(self.dbCnt)"
                        self.loadAllPhoto()
                        self.libraryPhotoCntLabel.text = "갤러리에 들어가 있는 사진 개수: \(self.fetchResult.count)"
                        self.currentUpdateLabel.text = "가장최근 동기화 시간: \(Date().dateToStringNormal(date: Date()))"
                    }
                }
            } catch {
                print("Realm 저장 중 에러 발생", error.localizedDescription)
            }
        }
    }

    func remove(object: PHAsset) {
        var count = 0
        DispatchQueue.global().sync {
            let realm = try! Realm()
            let objects = realm.objects(DataBaseModel.self)
            if let item = objects.filter("id == '\(object.localIdentifier)'").first {
                do {
                    try realm.write {
                        print("🌟 \(item.id) 사진 삭제 완료!")
                        realm.delete(item)
                        DispatchQueue.main.async {
                            self.dbCnt -= 1
                            self.loadAllPhoto()
                            self.appDBCntLabel.text = "동기화된 DB 개수 : \(self.dbCnt)"
                            self.libraryPhotoCntLabel.text = "갤러리에 들어가 있는 사진 개수: \(self.fetchResult.count)"
                            self.currentUpdateLabel.text = "가장최근 동기화 시간: \(Date().dateToStringNormal(date: Date()))"
                        }
                    }
                } catch {
                    print("Realm 삭제 중 에러 발생", error.localizedDescription)
                }
            }
        }
    }

    func removeAll() {
        DispatchQueue.global().sync {
            do {
                let realm = try Realm()
                try realm.write {
                    realm.deleteAll()
                    print("🌟 전체 사진 삭제 완료!")
                    DispatchQueue.main.async {
                        self.dbCnt = 0
                        self.appDBCntLabel.text = "동기화된 DB 개수 : \(self.dbCnt)"
                        self.currentUpdateLabel.text = "가장최근 동기화 시간: \(Date().dateToStringNormal(date: Date()))"
                    }
                }
            } catch {
                print("전체 삭제 중 에러 발생")
            }
        }
        
    }
    
    func changeData(asset: PHAsset) {
        DispatchQueue.global().sync {
            do {
                let realm = try Realm()
                let object = realm.objects(DataBaseModel.self)
                if let data = object.filter("id == '\(asset.localIdentifier)'").first {
                    try realm.write {
                        data.id = asset.localIdentifier
                        data.createdAt = Date().dateToString(date: asset.creationDate) ?? ""
                        data.lat = asset.location?.coordinate.latitude ?? 0
                        data.lng = asset.location?.coordinate.longitude ?? 0
                        data.isUpload = 0
                        data.localUpdatedAt = Date().dateToString(date: Date()) ?? ""
                        data.modificationDate = Date().dateToString(date: asset.modificationDate) ?? ""
                    }
                    DispatchQueue.main.async {
                        self.currentUpdateLabel.text = "가장최근 동기화 시간: \(Date().dateToStringNormal(date: Date()))"
                    }
                    print("✅ 데이터 수정 완료")
                }
            } catch {
                print("데이터 수정 중 오류 발생")
            }
        }
    }
    
    func writeRealm(item: PHAsset) -> DataBaseModel {
        let data = DataBaseModel()
        // 데이터 정의 구간
        data.id = item.localIdentifier
        data.createdAt = Date().dateToString(date: item.creationDate) ?? ""
        data.lat = item.location?.coordinate.latitude ?? 0
        data.lng = item.location?.coordinate.longitude ?? 0
        data.isUpload = 0
        data.localUpdatedAt = Date().dateToString(date: Date()) ?? ""
        data.modificationDate = Date().dateToString(date: item.modificationDate) ?? ""

        return data
    }
    
    
    func loadAllPhoto() {
        DispatchQueue.global().sync {
            let req = PHImageRequestOptions()
            req.isSynchronous = true
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            self.fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        }
    }
    
    func deleteLogic() {
        DispatchQueue.global(qos: .userInteractive).sync {
            let realm = try! Realm()
            let object = realm.objects(DataBaseModel.self)
            object.forEach { item in
                if PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).count == 0 {
                    print("삭제할 에셋", item)
                    do {
                        try realm.write {
                            realm.delete(item)
                            DispatchQueue.main.async {
                                self.dbCnt -= 1
                                self.appDBCntLabel.text = "동기화된 DB 개수 : \(self.dbCnt)"
                            }
                            print("삭제 완료")
                        }
                    } catch {
                        print("삭제 오류")
                    }
                }
            }
        }
        
    }
    
    func editLogic() {
        DispatchQueue.global().sync {
            let realm = try! Realm()
            var count = 0
            let object = realm.objects(DataBaseModel.self)
            self.fetchResult.enumerateObjects { asset, _, _ in
                if let data = object.filter("id == '\(asset.localIdentifier)' && modificationDate != '\(Date().dateToString(date: asset.modificationDate) ?? "")'").first {
                    print("DB상 시간: ", data.modificationDate ?? "")
                    print("바뀐 시간: ", Date().dateToString(date: asset.modificationDate) ?? "")
                    do {
                        try realm.write {
                            data.id = asset.localIdentifier
                            data.modificationDate = Date().dateToString(date: asset.modificationDate) ?? ""
                            data.lat = asset.location?.coordinate.longitude ?? 0.0
                            data.lng = asset.location?.coordinate.latitude ?? 0.0
                            data.isUpload = 0
                            data.localUpdatedAt = Date().dateToString(date: Date()) ?? ""

                        }
                        print("✅ 업데이트 성공!")
                        DispatchQueue.main.async {
                            self.currentUpdateLabel.text = "가장최근 동기화 시간: \(Date().dateToStringNormal(date: Date()))"
                            if count == 0 {
                                DispatchQueue.main.async {
                                    self.view.makeToast("✅ 수정된 사진을 업데이트 했습니다.")
                                }
                            }
                            count += 1
                        }
                    } catch {
                        print("업데이트 실패..")
                    }
                }
            }
        }
        
    }
}


// MARK: - PhotoLibrary Observer
extension ViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        self.addAssets.removeAll()
        self.deleteAssets.removeAll()
        self.changeAssets.removeAll()
        
        guard let changeDetail = changeInstance.changeDetails(for: fetchResult) else { return }

        let deleteAssets = changeDetail.removedObjects
        let addAssets = changeDetail.insertedObjects
        let changeAssets = changeDetail.changedObjects
        
        if !addAssets.isEmpty {

            addAssets.forEach { asset in
                let data = self.writeRealm(item: asset)
                add(object: data)
            }
        }

        if !deleteAssets.isEmpty {
            deleteAssets.forEach { asset in
                self.remove(object: asset)
            }
        }


        if !changeAssets.isEmpty {
            print("바뀐 사진들",changeAssets)
            changeAssets.forEach { item in
                changeData(asset: item)
            }
            
            DispatchQueue.main.async {
                self.view.makeToast("✅ 수정된 사진을 업데이트 했습니다.")
            }
            
        }
        
    }
}


// MARK: - Extensions
extension Int {
    var hour: Int {
        self / 3600
    }
    
    var minute: Int {
        ( self % 3600 ) / 60
    }
    
    var seconds: Int {
        (self % 60 )
    }
}

extension Date {
    func dateToString(date: Date?) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = .autoupdatingCurrent
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

        return dateFormatter.string(from: date!)
    }
    
    func dateToStringNormal(date: Date?) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = .autoupdatingCurrent
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.dateFormat = "MM월dd일 HH시mm분ss초"
        
        return dateFormatter.string(from: date!)
    }
}
