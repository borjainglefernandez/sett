//
//  WorkoutListVM.swift
//  Sett
//
//  Created by Borja Ingle-Fernandez on 6/16/23.
//

import UIKit
import CoreData

final class WorkoutsByDateVM: NSObject {
    
    public let workoutSortByVM: WorkoutSortByVM
    public var homeView: HomeView?
    private var cellVMs: [MonthListCellVM] = []
    private var isExpanded: [Bool] = []
    private var workoutsByMonth: [String: [Workout]] = [String: [Workout]]()
    lazy var fetchedResultsController: NSFetchedResultsController<Workout> = {
        return CoreDataBase.createFetchedResultsController(
                withEntityName: "Workout",
                expecting: Workout.self,
                sortDescriptors: [NSSortDescriptor(key: "startTime", ascending: self.workoutSortByVM.ascending)])
    }()
    
    // MARK: - Init
    init(workoutSortByVM: WorkoutSortByVM) {
        self.workoutSortByVM = workoutSortByVM
    }

    // MARK: - Configurations

    /// Puts each workout in the corresponding month and year
    private func setMonthYearWorkoutsDict(_ workoutsToAdd: [Workout]) {
        for workout in workoutsToAdd {
            guard let startTime = workout.startTime else { // Don't add if no startTime found
                continue
            }
            let month = Calendar.current.component(.month, from: startTime)
            let year = Calendar.current.component(.year, from: startTime)

            // Add month and year if it does not exist
            if !self.workoutsByMonth.keys.contains("\(month)/\(year)") {
                self.workoutsByMonth["\(month)/\(year)"] = []
            }

            self.workoutsByMonth["\(month)/\(year)"]?.append(workout)
        }
    }

    /// Initialize the cell view models from the workouts
    private func initCellVMs() {
        var sortedKeys = self.workoutsByMonth.keys.sorted() // chronological order
        if !self.workoutSortByVM.ascending {
            sortedKeys = sortedKeys.reversed() // reverse chronological order
        }
        
        for monthYear in sortedKeys {
            let viewModel = MonthListCellVM(monthYear: monthYear, 
                                            numWorkouts: workoutsByMonth[monthYear]?.count ?? 0,
                                            workoutSortByVM: self.workoutSortByVM)
            self.cellVMs.append(viewModel)
            self.isExpanded.append(true)
        }
    }

    /// Configure all the necessary variables
    public func configure() {
        CoreDataBase.configureFetchedResults(controller: self.fetchedResultsController, expecting: Workout.self, with: self)

        // Reset variables in case of update
        self.cellVMs = []
        self.workoutsByMonth = [String: [Workout]]()

        // Get workouts in order of start time
        guard let workoutsByStartTime = self.fetchedResultsController.fetchedObjects else {
            return
        }
        self.setMonthYearWorkoutsDict(workoutsByStartTime)
        self.initCellVMs()
    }

    // TODO: GET RID OF THIS
    private func getRandomDate() -> Date {

        var randomDate = DateComponents()
        randomDate.month = Int.random(in: 1...12)
        randomDate.day = Int.random(in: 1...27)
        randomDate.year = 2023
        if let date = Calendar.current.date(from: randomDate) {
            return date
        }
        return Date()
    }

    // MARK: - Actions
    public func addWorkout() {
        let randomTitleList = ["Push 1", "Push 2", "Pull 1", "Pull 2", "Leg 1", "Leg 2"]

        let newWorkout = Workout(context: CoreDataBase.context)

        newWorkout.rating = Double.random(in: 0...5)
        newWorkout.startTime = getRandomDate()
        newWorkout.title = randomTitleList.randomElement()
        CoreDataBase.save()

        DispatchQueue.main.async {
            self.configure()
        }
    }

    public func getWorkoutsLength() -> Int {
        if let workoutsLength = self.fetchedResultsController.fetchedObjects?.count {
            return workoutsLength
        }
        return 0
    }
}

// MARK: - Collection View Delegate
extension WorkoutsByDateVM: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.workoutsByMonth.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MonthListCell.cellIdentifier,
            for: indexPath
        ) as? MonthListCell else {
            fatalError("Unsupported cell")
        }

        cell.configure(with: cellVMs[indexPath.row],
                       at: indexPath, for: collectionView,
                       isExpanded: self.isExpanded[indexPath.row], delegate: self)
        cell.collapsibleContainerTopBar.changeButtonIcon() // Expand or collapse container

        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if isExpanded[indexPath.row] {

            return CGSize(
                    width: (collectionView.safeAreaLayoutGuide.layoutFrame.width - 20),
                    height: CGFloat(self.cellVMs[indexPath.row].numWorkouts * 43) + 31)
        }
        return CGSize(width: (collectionView.safeAreaLayoutGuide.layoutFrame.width - 20), height: 30)
    }
}
// MARK: - Expanded Cell Delegate
extension WorkoutsByDateVM: CollapsibleContainerTopBarDelegate {
    /// Collapse or Expand selected Month Workout Container
    ///
    /// - Parameters:
    ///   - indexPath: The index of the month workout container to expand or collapse
    ///   - collectionView: The collection view of the month workout container
    func collapseExpand(indexPath: IndexPath, collectionView: UICollectionView) {
        self.isExpanded[indexPath.row] = !self.isExpanded[indexPath.row]
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.8, delay: 0.0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.9,
                options: UIView.AnimationOptions.curveEaseInOut, animations: {
                collectionView.reloadItems(at: [indexPath])
            })
        }
    }
}

// MARK: - Fetched Results Controller Delegate
extension WorkoutsByDateVM: NSFetchedResultsControllerDelegate {
    // Update screen if CRUD conducted on Workouts
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        DispatchQueue.main.async {
            self.configure()
            self.homeView?.workoutsByMonthCollectionView.reloadData()
            self.homeView?.showHideMonthWorkoutsByMonthCollectionView()
        }
    }
}

// MARK: - Workouts Delegate
extension WorkoutsByDateVM: WorkoutsDelegate {
    func addWorkout(collectionView: UICollectionView) {
        self.addWorkout()
    }
}
