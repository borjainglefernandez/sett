//
//  RoutinesView.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 7/30/23.
//

import UIKit

class RoutinesView: UIView {
    
    let viewModel = RoutinesVM()
    
    // View for when there are no exercises to display
    public let emptyView: UILabel = EmptyLabel(frame: .zero, labelText: "No routines created yet!")
    
    // Collection view of the category exercise containers
    public let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.sectionInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        layout.scrollDirection = .vertical
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(RoutineDayOfTheWeekCell.self, forCellWithReuseIdentifier: RoutineDayOfTheWeekCell.cellIdentifier)
        collectionView.backgroundColor = .systemCyan
        collectionView.isHidden = true
        return collectionView
    }()

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.backgroundColor = .systemCyan
        self.translatesAutoresizingMaskIntoConstraints = false
        
        self.viewModel.configure()
        self.viewModel.routinesView = self
        self.setUpCollectionView()
        self.showHideCollectionView()
        
        self.addSubviews(self.collectionView, self.emptyView)
        self.addConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initialiser")
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            self.collectionView.topAnchor.constraint(equalTo: topAnchor),
            self.collectionView.leftAnchor.constraint(equalTo: leftAnchor),
            self.collectionView.rightAnchor.constraint(equalTo: rightAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            self.emptyView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.emptyView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
    
    // MARK: - Configurations
    private func setUpCollectionView() {
        self.collectionView.dataSource = self.viewModel
        self.collectionView.delegate = self.viewModel
    }
    
    // MARK: - Actions
    
    // Shows or hides collection view depending on whether or not there are workouts
    public func showHideCollectionView() {
        if self.viewModel.getRoutineCategoryLength() > 0 {
            self.collectionView.isHidden = false
            self.emptyView.isHidden = true
        } else {
            self.collectionView.isHidden = true
            self.emptyView.isHidden = false
        }
    }

}
