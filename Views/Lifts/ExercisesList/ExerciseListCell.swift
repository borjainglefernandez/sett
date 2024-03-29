//
//  ExerciseListCellTableViewCell.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 8/8/23.
//

import UIKit

class ExerciseListCell: UITableViewCell {
    
    static let cellIdentifier = "ExerciseListCell"

    // Each individual cell container
    private let containerView: UIView = {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear
        return containerView
    }()
    
    // Display title of the exercise
    private let titleLabel: UILabel = Label(title: "", fontSize: 12.0, weight: .regular)
    
    // Display type of the exercise
    private let exerciseTypeLabel: UILabel = Label(title: "", fontSize: 10.0, weight: .regular)
    
    // Arrow Icon
    private let arrowIconButton: UIButton = {
        let arrowIconButton = UIButton()
        arrowIconButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIImage.SymbolConfiguration(font: .systemFont(ofSize: 17, weight: .bold))
        arrowIconButton.tintColor = .label
        arrowIconButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        let iconImage = UIImage(systemName: "chevron.right")
        iconImage?.withTintColor(.label)
        arrowIconButton.setImage(iconImage, for: .normal)
        return arrowIconButton
    }()
    
    // Dividier
    private let divider: UIView = Divider()
    
    // MARK: - Init
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        self.backgroundColor = UIColor.clear // Allows for customisability of cell
        self.configureClearSelectedBackground()
        
        self.contentView.addSubviews(self.containerView, self.titleLabel, self.exerciseTypeLabel, self.arrowIconButton, self.divider)
        
        self.addConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initialiser")
    }
    
    override func prepareForReuse() {
        self.titleLabel.text = nil
        self.exerciseTypeLabel.text = nil
        self.divider.isHidden = false
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            self.containerView.topAnchor.constraint(equalTo: self.topAnchor),
            self.containerView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.containerView.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: 0.985),
            self.containerView.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.985),
            
            self.titleLabel.leftAnchor.constraint(equalToSystemSpacingAfter: self.leftAnchor, multiplier: 2),
            self.titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 5),
            
            self.exerciseTypeLabel.leftAnchor.constraint(equalTo: self.titleLabel.leftAnchor),
            self.exerciseTypeLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 5),
            
            self.arrowIconButton.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.arrowIconButton.rightAnchor.constraint(equalTo: self.rightAnchor, constant: -20),
            
            self.divider.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.95),
            self.divider.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.divider.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
    }
    
    // MARK: - Configurations
    public func configure(with viewModel: ExerciseListCellVM, showDivider: Bool = true) {
        self.titleLabel.text = viewModel.exercise.name
        self.exerciseTypeLabel.text = viewModel.exercise.type?.exerciseType.rawValue
        
        if !showDivider {
            self.divider.isHidden = true
        }
    }
}
