//
//  IconHelper.swift
//  Kontax Cam
//
//  Created by Kevin Laminto on 22/5/20.
//  Copyright © 2020 Kevin Laminto. All rights reserved.
//

import Foundation
import UIKit

struct IconHelper {
    
    static let shared = IconHelper()
    private init () { }
    
    /// Get the icon name along with the other state of the icon.
    ///
    /// This is a custom function created to support multi icon toggle on each buttons.
    ///
    /// - Parameters:
    ///   - currentIcon: The current icon
    ///   - iconImageArray: The icon's array. For example, a flash off icon, auto flash icon, etc.
    /// - Returns: The icon and its index value according to the array.
    func getIconName(currentIcon: String?, iconImageArray: [String]) -> (UIImage, Int?) {
        let currentIcon = currentIcon == nil ? iconImageArray[0] : currentIcon
        var nextIndex = iconImageArray.firstIndex { $0 == currentIcon }! + 1
        nextIndex = nextIndex >= iconImageArray.count ? 1 : nextIndex
        
        let image = IconHelper.shared.getIconImage(iconName: iconImageArray[nextIndex])
        image.accessibilityIdentifier = iconImageArray[nextIndex]
        
        return (image, nextIndex)
    }
    
    /// Get the icon in UImage form from the given icon name
    /// - Parameter iconName: The icon name in string format
    /// - Returns: The icon in UIImage
    func getIconImage(iconName: String) -> UIImage {
        if let systemImage = UIImage(systemName: iconName) {
            return systemImage.withRenderingMode(.alwaysTemplate)
        } else if let customImage = UIImage(named: iconName) {
            return customImage
        } else {
            return UIImage(systemName: "rectangle")!
        }
        
    }
    
}
