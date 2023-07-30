//
//  LiftsViewController.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 6/7/23.
//

import UIKit

final class LiftsViewController: UIViewController {
    
    private let topBar = TopBar(frame: .zero)
    
    // Title label for currently selected feed
    lazy var titleLabel: UILabel = TitleLabel(frame: .zero, title: self.routineExerciseMenuViewModel.mainMenuTitle)
    
    // Button to change between routines and exercises
    private let addButton: UIButton = IconButton(frame: .zero, imageName: "plus.circle")
    
    // Button to change menus
    private let changeMenuButton: UIButton = IconButton(frame: .zero, imageName: "arrowtriangle.down.fill", color: .white, fontSize: 12.0)
    
    private let routineExerciseMenuViewModel: RoutineExerciseMenuViewModel = RoutineExerciseMenuViewModel()
    
    private let routinesView: RoutinesView = RoutinesView()
    private let exercisesView: ExercisesView = ExercisesView()
    
    
    private func setUpMenu() {
        self.changeMenuButton.showsMenuAsPrimaryAction = true
        
        let changeWorkoutLabel = UIAction(title: self.routineExerciseMenuViewModel.changeMenuTitle, attributes: [], state: .off) { action in
            self.routineExerciseMenuViewModel.toggleType()
            self.titleLabel.text = self.routineExerciseMenuViewModel.mainMenuTitle
            self.setUpMenu()
            self.setUpContent()
        }
        
        self.changeMenuButton.menu = UIMenu(children: [changeWorkoutLabel])
    }
    
    private func setUpContent() {
        switch self.routineExerciseMenuViewModel.type {
        case .routine:
            self.routinesView.isHidden = false
            self.exercisesView.isHidden = true
        case .exercise:
            self.routinesView.isHidden = true
            self.exercisesView.isHidden = false
            
        }
    }
    
    // MARK: - LifeCycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemCyan
        
        self.setUpContent()
        self.setUpMenu()
        CoreDataBase.loadExercises()
        
        self.view.addSubviews(topBar, titleLabel, changeMenuButton, addButton, routinesView, exercisesView)
        self.addConstraints()
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            self.topBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.topBar.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.topBar.widthAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.95),
            
            self.titleLabel.leftAnchor.constraint(equalToSystemSpacingAfter: self.topBar.leftAnchor, multiplier: 2),
            self.titleLabel.centerYAnchor.constraint(equalTo: self.topBar.centerYAnchor),
            
            self.changeMenuButton.leftAnchor.constraint(equalTo: self.titleLabel.rightAnchor, constant: 8),
            self.changeMenuButton.centerYAnchor.constraint(equalTo: self.titleLabel.centerYAnchor),
            
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
}
