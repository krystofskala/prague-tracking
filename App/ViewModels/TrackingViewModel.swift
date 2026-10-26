import Foundation
import CoreLocation
import Combine
import StreetTrackerCore

@MainActor
final class TrackingViewModel: ObservableObject {
    @Published private(set) var graph = StreetGraph(segments: [:])
    @Published private(set) var isLoadingStreets = true
    @Published private(set) var passCounts: [String: Int] = [:]
    @Published private(set) var coverageFraction: Double = 0
    @Published private(set) var districtCoverage: [String: Double] = [:]
    @Published private(set) var isTracking = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastLocation: Coordinate?
    @Published private(set) var suggestions: [UnwalkedSuggestion] = []
    /// GPS points written to the walk log since the app started.
    @Published private(set) var loggedPoints = 0

    private let coverageStore: CoverageStore
    private var coverageSummary = CoverageSummary(graph: StreetGraph(segments: [:]), passCounts: [:])
    /// nil until the bundled street data has loaded.
    private var matcher: MapMatcher?
    private let locationTracker: LocationTracker
    private let motionMonitor = WalkingActivityMonitor()
    private var powerPolicy = PowerPolicy()
    private let persistence: CoveragePersistence
    private let trackLog = TrackLog()
    /// Remembered so tracking continues by itself if iOS ended the app
    /// mid-walk and it gets opened again.
    private static let trackingKey = "trackingOn"
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let persistence = CoveragePersistence()
        let savedCounts = persistence.loadPassCounts()

        self.persistence = persistence
        self.coverageStore = CoverageStore(passCounts: savedCounts)
        self.passCounts = savedCounts
        self.locationTracker = LocationTracker()

        locationTracker.onLocation = { [weak self] location in
            self?.handle(location: location)
        }
        locationTracker.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.authorizationStatus = status
            }
            .store(in: &cancellables)
        motionMonitor.$activity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activity in
                self?.activityChanged(activity)
            }
            .store(in: &cancellables)

        if UserDefaults.standard.bool(forKey: Self.trackingKey) {
            startTracking()
        }

        // Parsing ~13 MB of Prague streets, tagging districts and building
        // the spatial index takes a second or two; doing it here on the main
        // thread froze the app at launch.
        Task {
            let (graph, matcher) = await Task.detached(priority: .userInitiated) {
                let graph = Self.loadBundledGraph()
                return (graph, MapMatcher(graph: graph))
            }.value
            self.graph = graph
            self.matcher = matcher
            self.coverageSummary = CoverageSummary(graph: graph, passCounts: coverageStore.passCounts)
            publishCoverage()
            isLoadingStreets = false
        }
    }

    nonisolated private static func loadBundledGraph() -> StreetGraph {
        guard
            let url = Bundle.main.url(forResource: "prague_streets", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let graph = try? OSMLoader.loadGraph(fromOverpassJSON: data)
        else {
            return StreetGraph(segments: [:])
        }

        guard
            let districtsURL = Bundle.main.url(forResource: "prague_districts", withExtension: "json"),
            let districtsData = try? Data(contentsOf: districtsURL),
            let boundaries = try? DistrictTagger.loadBoundaries(fromOverpassJSON: districtsData)
        else {
            return graph
        }
        return DistrictTagger.tag(graph: graph, with: boundaries)
    }

    func requestPermission() {
        locationTracker.requestAuthorization()
    }

    func toggleTracking() {
        if locationTracker.isTracking {
            locationTracker.stopTracking()
            motionMonitor.stop()
            isTracking = false
            UserDefaults.standard.set(false, forKey: Self.trackingKey)
        } else {
            startTracking()
        }
    }

    private func startTracking() {
        powerPolicy = PowerPolicy()
        locationTracker.setLowPower(false)
        locationTracker.startTracking()
        motionMonitor.start()
        isTracking = true
        UserDefaults.standard.set(true, forKey: Self.trackingKey)
    }

    func refreshSuggestions(limit: Int = 20) {
        guard let lastLocation else { return }
        suggestions = RouteSuggester.nearestUnwalked(from: lastLocation, graph: graph, coverage: coverageStore, limit: limit)
    }

    private func handle(location: CLLocation) {
        let coord = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        lastLocation = coord
        // The delayed re-check below may not run while iOS suspends the app
        // between fixes, so re-evaluate on every fix too.
        applyPowerMode()

        // Log every fix (walking or not) before any filtering, so the whole
        // route with exact times survives even if matching rules change.
        let matched = matcher?.match(coord)
        let segment = matched.flatMap { graph.segments[$0.segmentID] }
        trackLog.append(
            location,
            isWalking: motionMonitor.isLikelyWalking,
            street: segment.map { TrackLog.StreetInfo(name: $0.name, district: $0.district) }
        )
        loggedPoints += 1

        guard motionMonitor.isLikelyWalking else { return }
        guard let match = matched else { return }
        // Fixes come every ~10 m; only a new pass changes counts, map and file.
        let length = graph.segments[match.segmentID]?.lengthMeters ?? .infinity
        guard coverageStore.recordFix(on: match.segmentID, at: location.timestamp, segmentLengthMeters: length) else { return }

        passCounts = coverageStore.passCounts
        coverageSummary.markWalked(match.segmentID)
        publishCoverage()
        persistence.savePassCounts(coverageStore.passCounts)
    }

    private func activityChanged(_ activity: PowerPolicy.Activity) {
        powerPolicy.update(activity, at: Date())
        applyPowerMode()
        if activity == .stationary {
            // Core Motion only reports changes, so check again once the
            // stationary delay has passed.
            let delay = powerPolicy.stationaryDelay + 1
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self?.applyPowerMode()
            }
        }
    }

    private func applyPowerMode() {
        locationTracker.setLowPower(powerPolicy.isLowPower(at: Date()))
    }

    private func publishCoverage() {
        coverageFraction = coverageSummary.fraction
        districtCoverage = coverageSummary.districtFractions
    }
}
