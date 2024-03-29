//
//  WeightPickerView.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 7/19/23.
//

import UIKit

final class WeightPickerView: UIView {

    private let viewModel: WorkoutGeneralStatsViewCellVM
    lazy var weightPicker: WeightPicker = WeightPicker(frame: self.frame, viewModel: self.viewModel)
    
    // MARK: - Init
    init(frame: CGRect, viewModel: WorkoutGeneralStatsViewCellVM) {
        self.viewModel = viewModel
        super.init(frame: frame)
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.layer.cornerRadius = 7.5

        self.configureBackgroundColor()

        self.addSubview(weightPicker)
        self.addConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initialiser")
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 50),
            self.heightAnchor.constraint(equalToConstant: 25),
            
            self.weightPicker.topAnchor.constraint(equalTo: self.topAnchor),
            self.weightPicker.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.weightPicker.rightAnchor.constraint(equalTo: self.rightAnchor),
            self.weightPicker.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
    }
    
    // MARK: - Configurations
    private func configureBackgroundColor() {
        var alphaComponent: Double = 0.3
        if self.traitCollection.userInterfaceStyle == .light {
            alphaComponent = 0.1
        }
        self.backgroundColor = .systemFill.withAlphaComponent(alphaComponent)
    }

}
