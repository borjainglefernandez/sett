//
//  WorkoutVM.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 7/14/23.
//

import UIKit
import CoreData

final class WorkoutGeneralStatsVM: NSObject {
    
    public let workout: Workout
    public var tableView: UITableView?
    private lazy var cellVMs: [WorkoutGeneralStatsViewCellVM] = {
        return WorkoutGeneralStatsViewType.allCases.compactMap { type in
            return WorkoutGeneralStatsViewCellVM(type: type, workout: self.workout)
        }
    }()
    lazy var fetchedResultsController: NSFetchedResultsController<Workout> = {
        return CoreDataBase.createFetchedResultsController(
                    withEntityName: "Workout",
                    expecting: Workout.self,
                    predicates: [NSPredicate(format: "SELF = %@", self.workout.objectID)])
    }()
    
    // MARK: - Init
    init(workout: Workout) {
        self.workout = workout
        super.init()
        
        CoreDataBase.configureFetchedResults(controller: self.fetchedResultsController, expecting: Workout.self, with: self)
    }
}

// MARK: - Table View Delegate
extension WorkoutGeneralStatsVM: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return cellVMs.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: WorkoutGeneralStatsViewCell.cellIdentifier,
            for: indexPath
        ) as? WorkoutGeneralStatsViewCell else {
            fatalError("Unsupported cell")
        }
        cell.configure(with: cellVMs[indexPath.row])

        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return tableView.safeAreaLayoutGuide.layoutFrame.height * (1.0 / CGFloat(self.cellVMs.count))
    }
}

// MARK: - Fetched Results Controller Delegate
extension WorkoutGeneralStatsVM: NSFetchedResultsControllerDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        guard let managedObject = anObject as? NSManagedObject else {
            return // Ensure the object is a managed object
        }
        self.tableView?.reloadData()
        
    }
}

// MARK: - Text Field Delegate
extension WorkoutGeneralStatsVM: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        self.workout.title = textField.text
        CoreDataBase.save()
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.selectAll(nil)
    }
}
