//
//  PhotoEditorViewController.swift
//  Kontax Cam
//
//  Created by Kevin Laminto on 30/9/20.
//  Copyright © 2020 Kevin Laminto. All rights reserved.
//

import UIKit
import Combine
import Backend

class PhotoEditorViewController: UIViewController {
    var image: UIImage! {
        didSet {
            editorPreview.image = image
        }
    }
    
    private var currentCollection = FilterCollection.aCollection
    private var filtersGestureEngine: FiltersGestureEngine!
    private let editorPreview = EditorPreview()
    private let lutImageFilter = LUTImageFilter()
    private var mStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.alignment = .center
        stackView.distribution = .fillEqually
        return stackView
    }()
    private let doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("import to lab".localized, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .label
        button.setTitleColor(.systemBackground, for: .normal)
        return button
    }()
    
    var editedImage = PassthroughSubject<UIImage, Never>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setNavigationBarTitle("")
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.topItem?.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        
        // Setup swipe gesture for filters
        filtersGestureEngine = FiltersGestureEngine(previewView: editorPreview)
        filtersGestureEngine.delegate = self
        
        setupActionButtons()
        setupView()
        setupConstraint()
    }
    
    private func setupView() {
        view.addSubview(editorPreview)
        view.addSubview(mStackView)
        view.addSubview(doneButton)
        
        doneButton.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
    }
    
    private func setupConstraint() {
        editorPreview.snp.makeConstraints { (make) in
            make.width.equalTo(self.view.frame.width * 0.95)
            make.height.equalTo(self.view.frame.height * 0.65)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.topMargin).offset(10)
            make.centerX.equalToSuperview()
        }
        
        mStackView.snp.makeConstraints { (make) in
            make.top.equalTo(editorPreview.snp.bottom).offset(20)
            make.width.equalToSuperview().multipliedBy(0.95)
            make.height.equalTo(44)
            make.centerX.equalToSuperview()
        }
        
        doneButton.snp.makeConstraints { (make) in
            make.width.equalToSuperview().multipliedBy(0.8)
            make.height.equalTo(50)
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottomMargin).offset(-20)
        }
    }
    
    private func setupActionButtons() {
        let iconNames = ["fx", "filters.icon", "square.and.arrow.up"]
        var buttonTag = 0
        let buttonWidth: CGFloat = self.view.frame.width * 0.175
        let buttonHeight: CGFloat = 35
        
        for name in iconNames {
            let button = UIButton()
            button.frame = CGRect(origin: .zero, size: CGSize(width: buttonWidth, height: buttonHeight))
            button.clipsToBounds = true
            button.setImage(IconHelper.shared.getIconImage(iconName: name), for: .normal)
            button.tintColor = .label
            button.imageView?.contentMode = .scaleAspectFit
            button.addTarget(self, action: #selector(actionButtonTapped(_:)), for: .touchUpInside)
            button.tag = buttonTag
            
            mStackView.addArrangedSubview(button)
            buttonTag += 1
        }
    }

    @objc private func actionButtonTapped(_ sender: UIButton) {
        switch sender.tag {
        case 0: break
        case 1:
            let vc = FiltersCollectionViewController(collectionViewLayout: UICollectionViewLayout())
            vc.delegate = self
            vc.selectedCollection = currentCollection

            let navController = UINavigationController(rootViewController: vc)
            navController.modalPresentationStyle = .fullScreen
            
            self.present(navController, animated: true, completion: nil)
            
        case 2:
            if let image = editorPreview.getEditedImage() {
                ShareHelper.shared.presentShare(withImage: image, toView: self)
            }
            
        default: break
        }
    }
    
    @objc private func doneButtonTapped() {
        if let image = editorPreview.getEditedImage() {
            editedImage.send(image)
            self.navigationController?.popViewController(animated: true)
        } else {
            AlertHelper.shared.presentOKAction(withTitle: "Something went wrong.".localized, andMessage: "We are unable to import the image. Please try again.".localized, to: self)
        }
    }
}

extension PhotoEditorViewController: FilterListDelegate {
    func filterListDidSelectCollection(_ collection: FilterCollection) {
        currentCollection = collection
        filtersGestureEngine.collectionCount = currentCollection.filters.count + 1
        if let processedImage = lutImageFilter.process(filterName: currentCollection.filters.first!, imageToEdit: image) {
            editorPreview.setEditedImage(image: processedImage)
            editorPreview.filterLabelView.titleLabel.text = currentCollection.filters.first!.rawValue.uppercased()
        }
    }
}

extension PhotoEditorViewController: FiltersGestureDelegate {
    func didSwipeToChangeFilter(withNewIndex newIndex: Int) {
        TapticHelper.shared.lightTaptic()
        if newIndex > 0 {
            if let processedImage = lutImageFilter.process(filterName: currentCollection.filters[newIndex - 1], imageToEdit: image) {
                editorPreview.setEditedImage(image: processedImage)
                editorPreview.filterLabelView.titleLabel.text = currentCollection.filters[newIndex - 1].rawValue.uppercased()
            }
        } else {
            editorPreview.setEditedImage(image: image)
            editorPreview.filterLabelView.titleLabel.text = "OFF"
        }
    }
}