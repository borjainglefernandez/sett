//
//  NotesViewController.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 7/18/23.
//

import UIKit

final class NotesViewController: UIViewController {
    
    private let viewModel: WorkoutGeneralStatsViewCellViewModel

    private let topBar: TopBar = TopBar(frame: .zero)
    
    private let closeButton: UIButton = IconButton(frame: .zero, imageName: "xmark.circle.fill")
    
    private let notesTitle: UILabel = TitleLabel(frame: .zero, title: "Notes")
    
    private let notesView: NotesView
    
    // MARK: - Init
    init(viewModel: WorkoutGeneralStatsViewCellViewModel) {
        self.viewModel = viewModel
        notesView = NotesView(frame: .zero, viewModel: self.viewModel)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initialiser")

    }
    
    // MARK: - LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemCyan
        view.addSubviews(self.topBar, self.closeButton, self.notesTitle, self.notesView)
        addConstraints()
        self.notesView.textView.becomeFirstResponder()
        self.closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            self.topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            self.topBar.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            self.topBar.widthAnchor.constraint(equalTo:view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.95),
            self.topBar.heightAnchor.constraint(equalToConstant: 30),
            
            self.notesTitle.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            self.notesTitle.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            
            self.closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            self.closeButton.rightAnchor.constraint(equalTo: topBar.rightAnchor, constant: -7),
            
            self.notesView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor),
            self.notesView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor),
            self.notesView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            self.notesView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - Actions
    @objc func close() {
        self.dismiss(animated: true)
    }
}