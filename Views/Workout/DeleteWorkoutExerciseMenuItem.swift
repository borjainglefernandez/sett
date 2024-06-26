//
//  DeleteExerciseMenuItem.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 4/8/24.
//

import Foundation
import UIKit

class DeleteWorkoutExerciseMenuItem: NSObject {
    
    private let workoutExercise: WorkoutExercise
    private let menuView: UIView
    
    init(workoutExercise: WorkoutExercise, menuView: UIView) {
        self.workoutExercise = workoutExercise
        self.menuView = menuView
    }
    
    public func deleteWorkoutExercise() {
        CoreDataBase.context.delete(self.workoutExercise)
        CoreDataBase.save()
    }
    
    public func getMenuItem() -> UIAction {
        let actionHandler: UIActionHandler = { _ in
            
            // Controller
            let deleteWorkoutExerciseAlertController = DeleteAlertViewController(
                title: "Remove \(String(describing: self.workoutExercise.exercise?.name ?? "")) " +
                    "from \(String(describing: self.workoutExercise.workout?.title ?? ""))?",
                deleteAction: self.deleteWorkoutExercise)

            if let parentViewController = self.menuView.getParentViewController(self.menuView) {
                parentViewController.present(deleteWorkoutExerciseAlertController, animated: true)
            }

        }
        
        return UIAction(
            title: "Delete Exercise",
            image: UIImage(systemName: "trash"),
            attributes: [.destructive],
            state: .off,
            handler: actionHandler
        )
    }
}
