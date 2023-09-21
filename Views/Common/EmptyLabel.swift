//
//  EmptyLabel.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 8/8/23.
//

import UIKit

class EmptyLabel: UILabel {
    
    // MARK: - Init
    init(frame: CGRect, labelText: String) {
        super.init(frame: frame)
        self.translatesAutoresizingMaskIntoConstraints = false
        
        self.textColor = .label
        self.font = .systemFont(ofSize: 17.0, weight: .bold)
        self.text = labelText
        self.textAlignment = .center
        self.isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initialiser")
    }
    
}
