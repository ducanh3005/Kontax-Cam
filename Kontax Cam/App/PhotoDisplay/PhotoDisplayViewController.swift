//
//  PhotoDisplayViewController.swift
//  Kontax Cam
//
//  Created by Kevin Laminto on 3/6/20.
//  Copyright © 2020 Kevin Laminto. All rights reserved.
//

import DTPhotoViewerController
import UIKit

protocol PhotoDisplayDelegate {
    /// Tells the delegate to share the photo at index
    func photoDisplayWillShare(photoAt index: Int)
    /// Tells the delegate to save  the photo at index
    func photoDisplayWillSave(photoAt index: Int)
    /// Tells the delegate to delete  the photo at index
    func photoDisplayWillDelete(photoAt index: Int)
    /// Tells the delegate that a new cell will be shown
    func photoDisplayWillChangeCell(atNewIndex index: Int)
}

class PhotoDisplayViewController: DTPhotoViewerController {
    
    override var prefersStatusBarHidden: Bool {
        return false
    }
    
    // MARK: - Variables
    private let toolImages = ["square.and.arrow.up", "square.and.arrow.down", "trash"]
    var images: [UIImage] = []
    lazy private var navView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    lazy private var toolView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    lazy var navTitleLabel: UILabel = {
        let v = UILabel()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.numberOfLines = 0
        v.font = .preferredFont(forTextStyle: .body)
        v.textAlignment = .center
        return v
    }()
    lazy private var closeButton: UIButton = {
        let v = UIButton(type: .close)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    lazy private var toolSV = SVHelper.shared.createSV(axis: .horizontal, alignment: .center, distribution: .fillEqually)
    lazy private var navSV = SVHelper.shared.createSV(axis: .horizontal, alignment: .center, distribution: .fillEqually)
    
    var photoDisplayDelegate: PhotoDisplayDelegate?
    
    // MARK: - View lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.scrollView.showsHorizontalScrollIndicator = false
        
        registerClassPhotoViewer(PhotoDisplayCollectionViewCell.self)
        self.backgroundColor = .systemBackground
        
        setupUI()
        setupConstraint()
        setupToolbar()
    }
    
    private func setupUI() {
        
        self.view.addSubview(navView)
        self.view.addSubview(toolView)
        
        navView.addBorder(side: .bottom, color: .systemGray6, width: 1)
        
        // Tool View
        for i in 0 ..< toolImages.count {
            let btn = UIButton()
            btn.setImage(IconHelper.shared.getIconImage(iconName: toolImages[i]), for: .normal)
            btn.tintColor = .label
            btn.tag = i
            btn.addTarget(self, action: #selector(toolButtonTapped), for: .touchUpInside)
            
            toolSV.addArrangedSubview(btn)
        }
        
        toolView.addSubview(toolSV)
        
        // Nav View
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        navView.addSubview(closeButton)
        navView.addSubview(navTitleLabel)
    }
    
    private func setupConstraint() {
        let barHeight = UINavigationController().navigationBar.frame.size.height
        
        navView.snp.makeConstraints { (make) in
            make.top.equalToSuperview()
            make.height.equalTo(barHeight + self.view.getSafeAreaInsets().top)
            make.width.equalToSuperview()
        }
        
        closeButton.snp.makeConstraints { (make) in
            make.left.equalToSuperview().offset(20)
            make.top.equalToSuperview().offset(self.view.getSafeAreaInsets().top)
        }
        
        navTitleLabel.snp.makeConstraints { (make) in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(self.view.getSafeAreaInsets().top)
        }
        
        toolView.snp.makeConstraints { (make) in
            make.bottom.equalToSuperview()
            make.width.equalToSuperview()
            make.height.equalTo(barHeight + self.view.getSafeAreaInsets().bottom)
        }
        
        toolSV.snp.makeConstraints { (make) in
            make.width.equalToSuperview()
            make.height.equalTo(barHeight)
            make.top.equalToSuperview()
        }
        
        toolSV.arrangedSubviews.forEach({
            $0.snp.makeConstraints { (make) in
                make.height.equalToSuperview()
            }
        })
        
    }
    
    private func setupToolbar() {
        navigationController?.setToolbarHidden(false, animated: false)
        let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        
        var items: [UIBarButtonItem] = []
        
        for i in 0 ..< toolImages.count {
            let btn = UIButton()
            btn.frame = CGRect(x: 0, y: 0, width: 100, height: 200)
            btn.setImage(IconHelper.shared.getIconImage(iconName: toolImages[i]), for: .normal)
            btn.tintColor = .label
            btn.tag = i
            btn.addTarget(self, action: #selector(toolButtonTapped), for: .touchUpInside)
            
            let toolBtn = UIBarButtonItem(customView: btn)
            items.append(toolBtn)
            if i != toolImages.count - 1 { items.append(flexible) }
        }
        
        self.toolbarItems = items
    }
    
    @objc private func toolButtonTapped(sender: UIButton) {
        switch sender.tag {
        case 0:
            photoDisplayDelegate?.photoDisplayWillShare(photoAt: self.currentPhotoIndex)
            
        case 1:
            photoDisplayDelegate?.photoDisplayWillSave(photoAt: self.currentPhotoIndex)
            
        case 2:
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            
            let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { (_) in
                self.photoDisplayDelegate?.photoDisplayWillDelete(photoAt: self.currentPhotoIndex)
                
                self.reloadData()
                let cv = self.scrollView as! UICollectionView
                if cv.numberOfItems(inSection: 0) == 0 { self.dismiss(animated: true, completion: nil) }
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            
            alert.addAction(deleteAction)
            alert.addAction(cancelAction)
            
            self.present(alert, animated: true, completion: nil)
            
        default: break
        }
    }
    
    @objc private func closeTapped() {
        hideInfoOverlayView(false)
        dismiss(animated: true, completion: nil)
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        photoDisplayDelegate?.photoDisplayWillChangeCell(atNewIndex: indexPath.row)
    }
    
    
    // MARK: - Secondary methods
    private func hideInfoOverlayView(_ animated: Bool) {
        configureOverlayViews(hidden: true, animated: animated)
    }
    
    private func showInfoOverlayView(_ animated: Bool) {
        configureOverlayViews(hidden: false, animated: animated)
    }
    
    private func configureOverlayViews(hidden: Bool, animated: Bool) {
        if hidden != navView.isHidden {
            let duration: TimeInterval = animated ? 0.2 : 0.0
            let alpha: CGFloat = hidden ? 0.0 : 1.0
            
            setOverlayElementsHidden(isHidden: false)
            
            UIView.animate(withDuration: duration, animations: {
                self.setOverlayElementsAlpha(alpha: alpha)
            }) { (_) in
                self.setOverlayElementsHidden(isHidden: hidden)
            }
        }
    }
    
    private func setOverlayElementsHidden(isHidden: Bool) {
        toolView.isHidden = isHidden
        navView.isHidden = isHidden
    }
    
    private func setOverlayElementsAlpha(alpha: CGFloat) {
        toolView.alpha = alpha
        navView.alpha = alpha
    }
    
    override func didReceiveTapGesture() {
        reverseInfoOverlayViewDisplayStatus()
    }
    
    // MARK: - DT Delegate
    @objc override func willZoomOnPhoto(at index: Int) {
        hideInfoOverlayView(false)
    }
    
    override func didEndZoomingOnPhoto(at index: Int, atScale scale: CGFloat) {
        if scale == 1 {
            showInfoOverlayView(true)
        }
    }
    
    override func didEndPresentingAnimation() {
        showInfoOverlayView(true)
    }
    
    override func willBegin(panGestureRecognizer gestureRecognizer: UIPanGestureRecognizer) {
        hideInfoOverlayView(false)
    }
    
    override func didReceiveDoubleTapGesture() {
        hideInfoOverlayView(false)
    }
    
    // Hide & Show info layer view
    private func reverseInfoOverlayViewDisplayStatus() {
        if zoomScale == 1.0 {
            if navView.isHidden == true {
                showInfoOverlayView(true)
            } else {
                hideInfoOverlayView(true)
            }
        }
    }
}
