//
//  InidividualExerciseModal.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 8/13/23.
//

import UIKit

class IndividualExerciseModal: UIView {
    
    private let viewModel: IndividualExerciseModalVM
    
    lazy var categoryListView: ModalTableView = {
        let categoryListVM = ModalTableVM(
            modalTableViewType: .category,
            modalTableViewSelectionType: .toggle,
            selectedCellCallBack: self.viewModel.selectCellCallback,
            category: self.viewModel.category)
        let categoryListView = ModalTableView(viewModel: categoryListVM)
        return categoryListView
    }()
    
    lazy var exerciseTypeListView: ModalTableView = {
        let exerciseTypeListVM = ModalTableVM(
            modalTableViewType: .exerciseType,
            modalTableViewSelectionType: .toggle,
            selectedCellCallBack: self.viewModel.selectCellCallback,
            exerciseType: self.viewModel.exercise?.type?.exerciseType)
        let exerciseTypeListView = ModalTableView(viewModel: exerciseTypeListVM)
        return exerciseTypeListView
    }()
    
    // MARK: - Init
    init(frame: CGRect = .zero, viewModel: IndividualExerciseModalVM) {
        self.viewModel = viewModel
        super.init(frame: frame)

        translatesAutoresizingMaskIntoConstraints = false
        
        self.addSubviews(self.categoryListView, self.exerciseTypeListView)
        self.addConstraints()
   }
    
    required init?(coder: NSCoder) {
        fatalError("Unsupported initialiser")
    }
    
    // MARK: - Constraints
    private func addConstraints() {
        NSLayoutConstraint.activate([
            self.categoryListView.topAnchor.constraint(equalTo: self.topAnchor),
            self.categoryListView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.categoryListView.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.95),
            self.categoryListView.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: 0.4),
            
            self.exerciseTypeListView.topAnchor.constraint(equalTo: self.categoryListView.bottomAnchor, constant: 30),
            self.exerciseTypeListView.centerXAnchor.constraint(equalTo: self.categoryListView.centerXAnchor),
            self.exerciseTypeListView.widthAnchor.constraint(equalTo: self.categoryListView.widthAnchor),
            self.exerciseTypeListView.heightAnchor.constraint(equalTo: self.categoryListView.heightAnchor)
        ])
    }
    
}
