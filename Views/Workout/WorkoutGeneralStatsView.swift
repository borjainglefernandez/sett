//
//  WorkoutGeneralStatsView.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 7/14/23.
//

import UIKit

final class WorkoutGeneralStatsView: UIView {
    
    private let viewModel: WorkoutViewModel
    
    
    // Top bar of the general stats view container
    private let topBar: UIView = {
        let topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = .systemGray4
        topBar.layer.cornerRadius = 15
        topBar.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
        return topBar
    }()
    
    // Table View for each category of general stats
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .systemGray3.withAlphaComponent(0.44)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(WorkoutGeneralStatsViewCell.self, forCellReuseIdentifier: WorkoutGeneralStatsViewCell.cellIdentifier)
        tableView.layer.cornerRadius = 15
        tableView.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
        tableView.separatorStyle = .none
        tableView.isScrollEnabled = false
        tableView.autoresizingMask = .flexibleHeight
        return tableView
    }()
    
    // MARK: - Init
    init(frame: CGRect, viewModel: WorkoutViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        self.addSubviews(topBar, tableView)
        setUpTableView()
        self.addConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initializer")
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            topBar.centerXAnchor.constraint(equalTo: centerXAnchor),
            topBar.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.95),
            topBar.heightAnchor.constraint(equalToConstant: 30),
            
            tableView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            tableView.leftAnchor.constraint(equalTo: topBar.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: topBar.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    private func setUpTableView() {
        self.tableView.dataSource = self.viewModel
        self.tableView.delegate = self.viewModel
    }
    
}