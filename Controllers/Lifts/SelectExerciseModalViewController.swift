//
//  SelectExerciseModalViewController.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 8/31/23.
//

import UIKit

class SelectExerciseModalViewController: UIViewController {
    
    private let viewModel: SelectExerciseModalVM
    
    // Cancel Button
    private let cancelButton: UIButton = IconButton(frame: .zero, imageName: "x.circle")
    
    // Modal Title
    private let titleLabel: Label = Label(title: "Exercise Selection")
    
    // Create New Exercise Button
    private let createNewExerciseButton: UIButton = IconButton(imageName: "plus.circle")
    
    // Confirm Button
    private let confirmButton: UIButton = IconButton(frame: .zero, imageName: "checkmark.circle")
    
    private let selectExerciseModal: SelectExerciseModal
        
    // MARK: - Init
    init(viewModel: SelectExerciseModalVM) {
        self.viewModel = viewModel
        self.selectExerciseModal = SelectExerciseModal(viewModel: self.viewModel)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initialiser")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        self.view.backgroundColor = .systemGray6
        
        self.cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        self.confirmButton.addTarget(self, action: #selector(confirm), for: .touchUpInside)
        self.createNewExerciseButton.addTarget(self, action: #selector(createNewExercise), for: .touchUpInside)

        self.view.addSubviews(self.cancelButton, self.titleLabel, self.createNewExerciseButton, self.confirmButton, self.selectExerciseModal)
        self.addConstraints()
        super.viewDidLoad()
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            self.cancelButton.leftAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leftAnchor, constant: 30),
            self.cancelButton.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            
            self.titleLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.titleLabel.centerYAnchor.constraint(equalTo: self.cancelButton.centerYAnchor),
            
            self.confirmButton.rightAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.rightAnchor, constant: -30),
            self.confirmButton.centerYAnchor.constraint(equalTo: self.titleLabel.centerYAnchor),
            
            self.createNewExerciseButton.rightAnchor.constraint(equalTo: self.confirmButton.leftAnchor, constant: -10),
            self.createNewExerciseButton.centerYAnchor.constraint(equalTo: self.confirmButton.centerYAnchor),
            
            self.selectExerciseModal.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 30),
            self.selectExerciseModal.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            self.selectExerciseModal.leftAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leftAnchor),
            self.selectExerciseModal.rightAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.rightAnchor)
        ])
    }
    
    // MARK: - Actions
    @objc func cancel() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func confirm() {
        if !self.viewModel.confirmExerciseSelection() {
            // Controller
            let incompleteSelectionViewController = UIAlertController(title: "Select a valid exercise", message: "", preferredStyle: .alert)
            
            incompleteSelectionViewController.addAction(UIAlertAction(title: "Try Again", style: .default))
            
            self.present(incompleteSelectionViewController, animated: true)
        } else {
            // Dismiss both this and preceding view controller
            self.presentingViewController?.presentingViewController?.dismiss(animated: true, completion: nil)

        }
    }
    
    @objc func createNewExercise() {
        let individualExerciseModalViewController = IndividualExerciseModalViewController(category: self.viewModel.category)
        individualExerciseModalViewController.isModalInPresentation = true // Disable dismissing of modal
        self.present(individualExerciseModalViewController, animated: true, completion: nil)
    }

}
