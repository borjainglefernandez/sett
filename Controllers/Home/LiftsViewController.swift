//
//  LiftsViewController.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 6/7/23.
//

import UIKit

final class LiftsViewController: UIViewController {
    
    private let topBar = MenuBar(frame: .zero)
    
    // Button to change menus
    private let changeMenuButton: UIButton = IconButton(frame: .zero, imageName: "arrowtriangle.down.fill", color: .label, fontSize: 12.0)
    
    // Title label for currently selected feed
    lazy var titleLabel: UILabel = Label(frame: .zero, title: self.routineExerciseMenuVM.mainMenuTitle)
    
    // Button to change between routines and exercises
    private let addButton: UIButton = IconButton(frame: .zero, imageName: "plus.circle")
    
    private let routineExerciseMenuVM: RoutineExerciseMenuVM = RoutineExerciseMenuVM()
    
    private let routinesView: RoutinesView = RoutinesView()
    private let exercisesView: ExercisesView = ExercisesView()
    
    private func setUpRoutineOrCategoryMenu() {
        self.changeMenuButton.showsMenuAsPrimaryAction = true
        
        let changeWorkoutLabel = UIAction(title: self.routineExerciseMenuVM.changeMenuTitle, attributes: [], state: .off) { _ in
            self.routineExerciseMenuVM.toggleType()
            self.titleLabel.text = self.routineExerciseMenuVM.mainMenuTitle
            self.setUpRoutineOrCategoryMenu()
            self.setUpContent()
        }
        
        self.changeMenuButton.menu = UIMenu(children: [changeWorkoutLabel])
    }
    
    private func setUpContent() {
        switch self.routineExerciseMenuVM.type {
        case .routine:
            self.routinesView.isHidden = false
            self.exercisesView.isHidden = true
            self.setUpAddRoutineButton()
        case .exercise:
            self.routinesView.isHidden = true
            self.exercisesView.isHidden = false
            self.setUpAddCategoryButton()
            
        }
    }
    
    private func setUpAddCategoryButton() {
        if let target = self.addButton.allTargets.first as? NSObject {
            self.addButton.removeTarget(target, action: #selector(addRoutine), for: .touchUpInside)
        }
        self.addButton.addTarget(self, action: #selector(addCategory), for: .touchUpInside)
    }
    
    private func setUpAddRoutineButton() {
        if let target = self.addButton.allTargets.first as? NSObject {
            self.addButton.removeTarget(target, action: #selector(addCategory), for: .touchUpInside)
        }
        self.addButton.addTarget(self, action: #selector(addRoutine), for: .touchUpInside)
    }
    
    // MARK: - LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemCyan
        
        self.setUpContent()
        self.setUpRoutineOrCategoryMenu()
        
        self.view.addSubviews(topBar, titleLabel, changeMenuButton, addButton, routinesView, exercisesView)
        self.addConstraints()
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            self.topBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.topBar.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.topBar.heightAnchor.constraint(equalToConstant: 30),
            self.topBar.widthAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.95),
            
            self.changeMenuButton.leftAnchor.constraint(equalToSystemSpacingAfter: self.topBar.leftAnchor, multiplier: 2),
            self.changeMenuButton.centerYAnchor.constraint(equalTo: self.topBar.centerYAnchor),
            
            self.titleLabel.leftAnchor.constraint(equalTo: self.changeMenuButton.rightAnchor, constant: 8),
            self.titleLabel.centerYAnchor.constraint(equalTo: self.changeMenuButton.centerYAnchor),
            
            self.addButton.centerYAnchor.constraint(equalTo: self.topBar.centerYAnchor),
            self.addButton.rightAnchor.constraint(equalTo: self.topBar.rightAnchor, constant: -15),

            self.routinesView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            self.routinesView.leftAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leftAnchor),
            self.routinesView.rightAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.rightAnchor),
            self.routinesView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            
            self.exercisesView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            self.exercisesView.leftAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leftAnchor),
            self.exercisesView.rightAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.rightAnchor),
            self.exercisesView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)

        ])
    }
    
    // MARK: - Actions
    @objc func addRoutine() {
        // Navigate to routine screen with no routine so new one gets created
        let individualRoutineVM: IndividualRoutineVM = IndividualRoutineVM()
        let individualRoutineViewController: IndividualRoutineViewController = IndividualRoutineViewController(viewModel: individualRoutineVM)
        
        individualRoutineViewController.modalPresentationStyle = .fullScreen
        present(individualRoutineViewController, animated: true, completion: nil)
    }
    
    @objc func addCategory() {
        let addCategoryVM: AddCategoryVM = AddCategoryVM()
        present(addCategoryVM.alertController, animated: true, completion: nil)
    }
    
    public func addExercise(category: Category, exercise: Exercise? = nil) {
        // Navigate to add exercise screen
        let individualExerciseModalViewController = IndividualExerciseModalViewController(category: category, exercise: exercise)
        individualExerciseModalViewController.isModalInPresentation = true // Disable dismissing of modal
        self.present(individualExerciseModalViewController, animated: true)
    }
}
