//
//  SettList.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 10/17/23.
//

import UIKit

class SettListView: UIView {
    
    private var viewModel: SettListVM?
    
    // Table View for routines in each category
    public let tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .systemGray3.withAlphaComponent(0.44)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(SettListCell.self, forCellReuseIdentifier: SettListCell.cellIdentifier)
        tableView.register(SettListActionView.self, forCellReuseIdentifier: SettListActionView.cellIdentifier)
        tableView.isScrollEnabled = false
        tableView.separatorStyle = UITableViewCell.SeparatorStyle.none
        tableView.layer.cornerRadius = 15
        tableView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        return tableView
    }()
    
    // Container for workout exercise buttons
    public let workoutExercisesButtonsContainer: UIView = {
        let workoutExercisesButtonsContainer = UIView()
        workoutExercisesButtonsContainer.translatesAutoresizingMaskIntoConstraints = false
        workoutExercisesButtonsContainer.backgroundColor = .systemGray3.withAlphaComponent(0.44)
        workoutExercisesButtonsContainer.layer.cornerRadius = 15
        workoutExercisesButtonsContainer.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        return workoutExercisesButtonsContainer
    }()
    
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.translatesAutoresizingMaskIntoConstraints = false
        
        self.addSubviews(self.tableView)
        self.addConstraints()
    }
    required init?(coder: NSCoder) {
        fatalError("Unsupported initialiser")
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            self.tableView.topAnchor.constraint(equalTo: self.topAnchor),
            self.tableView.leftAnchor.constraint(equalTo: self.leftAnchor),
            self.tableView.rightAnchor.constraint(equalTo: self.rightAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

    }
    
    // MARK: - Configurations
    public func configure(with viewModel: SettListVM) {
        self.viewModel = viewModel
        self.setUpTableView()
    }
    
    private func setUpTableView() {
        self.tableView.dataSource = self.viewModel
        self.tableView.delegate = self.viewModel
        self.viewModel?.tableView = self.tableView
        self.tableView.reloadData()
    }

}
