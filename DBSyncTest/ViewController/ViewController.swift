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

    @IBOutlet weak var scanStopButton: UIButton!
    @IBOutlet weak var scanStartButton: UIButton!
    @IBOutlet weak var notScanPersonLabel: UILabel!
    @IBOutlet weak var personCntLabel: UILabel!
    @IBOutlet weak var locationInfoLabel: UILabel!
    @IBOutlet weak var reBuildButton: UIButton!
    @IBOutlet weak var currentUpdateLabel: UILabel!
    @IBOutlet weak var libraryPhotoCntLabel: UILabel!
    @IBOutlet weak var syncEndDateLabel: UILabel!
    @IBOutlet weak var syncStartDateLabel: UILabel!
    @IBOutlet weak var circleView: UIActivityIndicatorView!
    @IBOutlet weak var appDBCntLabel: UILabel!
    @IBOutlet weak var syncMinus: UILabel!
    private var imageSegmentator: ImageSegmentator?
    private var resetBool: Bool = false
    private var fetchResult = PHFetchResult<PHAsset>()
    private var segmentationInput: UIImage?
    private var targetImage: UIImage?
    private var segmentationInfo: [SegInfo] = []
    var classifierQueue = Queue<PHAsset>()
    /// Image segmentation result.
    private var segmentationResult: SegmentationResult?
    
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
    var personCount = 0
    public var globalTimer = Timer()
    override func viewDidLoad() {
        super.viewDidLoad()
        PHPhotoLibrary.shared().register(self)
        // 버튼 세팅
        configureButton()
        // Initialize an image segmentator instance.
        ImageSegmentator.newInstance { [weak self] result in
            guard let self = self else { return }
          switch result {
          case let .success(segmentator):
            // Store the initialized instance for use.
            self.imageSegmentator = segmentator
          case .error(_):
            print("Failed to initialize.")
          }
        }
        
        // 데이터 전체 세팅
        setAllData()
    }

    func setTimer() {
        self.globalTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(checkCPU), userInfo: nil, repeats: true)
    }
    
    func configureButton() {
        syncButton.addTarget(self, action: #selector(syncAction), for: .touchUpInside)
        reBuildButton.addTarget(self, action: #selector(reBuildAction), for: .touchUpInside)
        scanStartButton.addTarget(self, action: #selector(scanStartAction), for: .touchUpInside)
        scanStopButton.addTarget(self, action: #selector(scanStopAction), for: .touchUpInside)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

}

extension ViewController {
    
    static var memortUsage: Double {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        var used: UInt64 = 0
        if result == KERN_SUCCESS { used = UInt64(taskInfo.phys_footprint) }
        
        let total = ProcessInfo.processInfo.physicalMemory
        let bytesInMegabyte = 1024.0 * 1024.0
        let usedMemory: Double = Double(used) / bytesInMegabyte
        let totalMemory: Double = Double(total) / bytesInMegabyte
        print(String(format: "%.2f MB / %.0f MB", usedMemory, totalMemory))
        return usedMemory
    }
    
    static var cpuUsage: Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)],
                                    thread_flavor_t(THREAD_BASIC_INFO),
                                    $0,
                                    &threadInfoCount)
                    }
                }
                
                guard infoResult == KERN_SUCCESS else { break }
                
                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU = (totalUsageOfCPU + (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0))
                    
                }
            }
        }
        
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        print(String(format: "CPU: %.1f", totalUsageOfCPU))
        return totalUsageOfCPU
    }
    
    func hostCPULoadInfo() -> host_cpu_load_info? {
        let HOST_CPU_LOAD_INFO_COUNT = MemoryLayout<host_cpu_load_info>.stride/MemoryLayout<integer_t>.stride
        var size = mach_msg_type_number_t(HOST_CPU_LOAD_INFO_COUNT)
        var cpuLoadInfo = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: HOST_CPU_LOAD_INFO_COUNT) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        if result != KERN_SUCCESS{
            print("Error  - \(#file): \(#function) - kern_result_t = \(result)")
            return nil
        }
        return cpuLoadInfo
    }
}


// MARK: - objc Functions
extension ViewController {
    
    @objc
    func scanStopAction() {
        self.globalTimer.invalidate()
    }
    
    @objc
    func scanStartAction() {
        self.globalTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(checkCPU), userInfo: nil, repeats: true)
    }
    
    @objc
    func checkCPU() {
        
        if ViewController.cpuUsage < 30.0 {
//            DispatchQueue.global().async {
//                //self.imageView.image = image
//                self.runSegmentation(UIImage(named: "test")!, asset: PHAsset())
//                print("이미지 넣음")
//            }
            
            if !self.classifierQueue.isEmpty() {
                guard let asset = self.classifierQueue.dequeue() else { return }
                DispatchQueue.global().async {
                    asset.requestContentEditingInput(with: nil) { image, _ in
                        guard let image = image?.displaySizeImage else { return }
                        //self.imageView.image = image
                        self.runSegmentation(image, asset: asset)

                        print("이미지 넣음")
                    }
                }
                DispatchQueue.main.async {
                    self.notScanPersonLabel.text = "사람 파악 남은 사진 수 : \(self.classifierQueue.count)"
                }
                UserDefaults.standard.set(self.classifierQueue.count, forKey: "ClassifierCnt")
            }
        }
    }
    
    @objc
    func reBuildAction() {
        resetBool = true
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
        self.classifierQueue.clear()
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
                self.classifierQueue.enqueue(element: asset)
                let realm = try! Realm()
                if let _ = realm.objects(DataBaseModel.self).filter("id == '\(asset.localIdentifier)'").first {
                } else {
                    let item = QueueModel(dbModel: asset, queueType: .add)
                    self.queue.enqueue(element: item)
                    
                }

                //self.count += 1
            }
            
            if resetBool {
                UserDefaults.standard.set(self.classifierQueue.count, forKey: "ClassifierCnt")
                print("세팅", self.classifierQueue.count)
                resetBool = false
            }
            
            print("마지막 업데이트 할 때 큐에 남아있던 개수", UserDefaults.standard.integer(forKey: "ClassifierCnt"))
            
            if UserDefaults.standard.integer(forKey: "ClassifierCnt") != 0 {
                while classifierQueue.count > UserDefaults.standard.integer(forKey: "ClassifierCnt") {
                    let _ = classifierQueue.dequeue()
                }
            }
            
            print("큐에 남아있는 개수", classifierQueue.count)
        }
        
        DispatchQueue.global().sync {
            do {
                let realm = try Realm()
                let count = realm.objects(DataBaseModel.self).filter("includedPerson == true").count
                personCount = count
                print("DB에 저장된 사람 수 ",count)
            } catch {
                print("에러~")
            }
        }

        // 6. 큐에 들어간 사진들 돌리기
        perform(#selector(startAction), with: nil, afterDelay: 0.5)
        perform(#selector(delayAction), with: nil, afterDelay: 0.8)
        perform(#selector(catchPerson), with: nil, afterDelay: 3)
    }
    
    @objc
    func catchPerson() {
        setTimer()
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
        data.includedPerson = false
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

extension ViewController {
    func runSegmentation(_ image: UIImage, asset: PHAsset) {
      clearResults()

      // Rotate target image to .up orientation to avoid potential orientation misalignment.
      guard let targetImage = image.transformOrientationToUp() else {
        return
      }

      // Make sure that image segmentator is initialized.
      guard imageSegmentator != nil else {
        return
      }
        self.targetImage = targetImage
      // Cache the target image.

      // Center-crop the target image if the user has enabled the option.
      //let image = targetImage.cropCenter()

      // Cache the potentially cropped image as input to the segmentation model.
      segmentationInput = targetImage

      // Show the potentially cropped image on screen.

      // Make sure that the image is ready before running segmentation.
      guard targetImage != nil else {
        return
      }

      // Run image segmentation.
      imageSegmentator?.runSegmentation(
        targetImage,
        completion: { result in
          // Unlock the crop switch

          // Show the segmentation result on screen
          switch result {
          case let .success(segmentationResult):
            self.segmentationResult = segmentationResult

            // Show result metadata
              self.showClassLegend(segmentationResult, asset: asset)

            // Enable switching between different display mode: input, segmentation, overlay
          case let .error(error):
              print("에러")
          }
        })
    }

    /// Show color legend of each class found in the image.
    private func showClassLegend(_ segmentationResult: SegmentationResult, asset: PHAsset) {
      // Loop through the classes founded in the image.
        
        var seg = SegInfo(preprocessing: Int(segmentationResult.preprocessingTime * 1000),
                          modelInference: Int(segmentationResult.inferenceTime * 1000),
                          postprocessing: Int(segmentationResult.postProcessingTime * 1000),
                          visualization: Int(segmentationResult.visualizationTime * 1000), isPerson: true)
        
        if segmentationResult.colorLegend.contains(where: { $0.key == "person"} ) {
            
            print("사람임",segmentationResult.colorLegend)
            
            DispatchQueue.main.async {
                self.personCount += 1
                self.personCntLabel.text = "사람있는 사진 개수: \(self.personCount)"
            }
            
            seg.isPerson = false
            do {
                let realm = try Realm()
                let object = realm.objects(DataBaseModel.self)
                if let data = object.filter("id == '\(asset.localIdentifier)'").first {
                    try realm.write {
                        data.includedPerson = true
                    }
                    DispatchQueue.main.async {
                        self.currentUpdateLabel.text = "가장최근 동기화 시간: \(Date().dateToStringNormal(date: Date()))"
                    }
                    print("✅ 사람 여부 수정 완료")
                }
            } catch {
                print("Person")
            }
            
            print("Yes")
        }
    }
    
    /// Clear result from previous run to prepare for new segmentation run.
    private func clearResults() {
      print("Running inference with TensorFlow Lite...")
    }

}
