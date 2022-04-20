//
//  CollectionViewCell.swift
//  DBSyncTest
//
//  Created by Tabber on 2022/04/19.
//

import UIKit

class CollectionViewCell: UICollectionViewCell {
    static let cellId = "CollectionViewCell"
    @IBOutlet weak var imageView: UIImageView!
    
    func configureImage(image: UIImage) {
        imageView.image = image
    }
}
