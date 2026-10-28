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
    /// Today's route as recorded (accurate fixes only), drawn under the streets.
    @Published private(set) var todaysRoute: [Coordinate] = []
    @Published var mode: PowerPolicy.Mode {
        didSet {
            powerPolicy.mode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            trackLog.appendEvent("rezim", mode == .precise ? "přesný" : "úsporný")
        }
    }

    private let coverageStore: CoverageStore
    private var coverageSummary = CoverageSummary(graph: StreetGraph(segments: [:]), passCounts: [:])
    /// nil until the bundled street data has loaded.
    private var matcher: MapMatcher?
    private let locationTracker: LocationTracker
    private let motionMonitor = WalkingActivityMonitor()
    private var powerPolicy = PowerPolicy()
    private var speedDetector = WalkingSpeedDetector()
    /// Fixes worse than this still go to the log, but don't snap to streets
    /// or draw on the map.
    private static let matchAccuracy: Double = 50
    /// In saving mode while riding or standing, process one fix this often.
    private static let lowPowerInterval: TimeInterval = 30
    private var lastProcessedFix: Date?
    private var wasLowPower = false
    private let persistence: CoveragePersistence
    private let trackLog = TrackLog()
    /// Remembered so tracking continues by itself if iOS ended the app
    /// mid-walk and it gets opened again.
    private static let trackingKey = "trackingOn"
    private static let modeKey = "trackingMode"
    private var cancellables: Set<AnyCancellable> = []

    init(launchedForLocation: Bool = false) {
        let persistence = CoveragePersistence()
        let savedCounts = persistence.loadPassCounts()

        self.persistence = persistence
        self.coverageStore = CoverageStore(passCounts: savedCounts)
        self.passCounts = savedCounts
        self.locationTracker = LocationTracker()
        let mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(PowerPolicy.Mode.init(rawValue:)) ?? .precise
        self.mode = mode
        self.powerPolicy = PowerPolicy(mode: mode)
        self.todaysRoute = trackLog.todaysRoute(maxAccuracy: Self.matchAccuracy).map {
            Coordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        trackLog.appendEvent("start_appky", launchedForLocation ? "iOS appku znovu spustil kvůli poloze" : "spuštěno")

        locationTracker.onLocation = { [weak self] location in
            self?.handle(location: location)
        }
        locationTracker.onEvent = { [weak self] kind, detail in
            self?.trackLog.appendEvent(kind, detail)
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
            trackLog.appendEvent("sber", "zastaveno")
        } else {
            startTracking()
        }
    }

    private func startTracking() {
        powerPolicy = PowerPolicy(mode: mode)
        speedDetector = WalkingSpeedDetector()
        wasLowPower = false
        locationTracker.startTracking()
        motionMonitor.start()
        isTracking = true
        UserDefaults.standard.set(true, forKey: Self.trackingKey)
        trackLog.appendEvent("sber", "spuštěno")
    }

    func refreshSuggestions(limit: Int = 20) {
        guard let lastLocation else { return }
        suggestions = RouteSuggester.nearestUnwalked(from: lastLocation, graph: graph, coverage: coverageStore, limit: limit)
    }

    private func handle(location: CLLocation) {
        let now = location.timestamp
        speedDetector.observe(speed: location.speed, at: now)
        if speedDetector.isWalking(at: now) {
            // Core Motion can lag minutes behind after a ride; a steady
            // walking pace is enough to leave saving mode.
            powerPolicy.update(.walking, at: now)
        }
        // The delayed re-check below may not run while iOS suspends the app
        // between fixes, so re-evaluate on every fix too.
        let lowPower = applyPowerMode()
        if lowPower, let last = lastProcessedFix, now.timeIntervalSince(last) < Self.lowPowerInterval {
            return
        }
        lastProcessedFix = now

        let isAccurate = location.horizontalAccuracy >= 0 && location.horizontalAccuracy < Self.matchAccuracy
        let coord = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let walking = motionMonitor.isLikelyWalking || speedDetector.isWalking(at: now)

        // Log every fix (walking or not, accurate or not) before any
        // filtering, so the whole route with exact times survives and can be
        // recomputed if matching rules change.
        let matched = isAccurate ? matcher?.match(coord) : nil
        let segment = matched.flatMap { graph.segments[$0.segmentID] }
        trackLog.append(
            location,
            isWalking: walking,
            street: segment.map { TrackLog.StreetInfo(name: $0.name, district: $0.district) }
        )
        loggedPoints += 1
        guard isAccurate else { return }
        lastLocation = coord
        todaysRoute.append(coord)

        guard walking else { return }
        guard let match = matched else { return }
        // Fixes come every few metres; only a new pass changes counts, map and file.
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

    @discardableResult
    private func applyPowerMode() -> Bool {
        let lowPower = powerPolicy.isLowPower(at: Date())
        if lowPower != wasLowPower {
            wasLowPower = lowPower
            trackLog.appendEvent("uspora", lowPower ? "zapnuta (řidší body)" : "vypnuta (všechny body)")
        }
        return lowPower
    }

    private func publishCoverage() {
        coverageFraction = coverageSummary.fraction
        districtCoverage = coverageSummary.districtFractions
    }
}
