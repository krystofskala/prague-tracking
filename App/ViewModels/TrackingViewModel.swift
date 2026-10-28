import Foundation
import CoreLocation
import Combine
import UIKit
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
    /// Today's route as recorded (accurate fixes at least `routeSpacing`
    /// apart), drawn under the streets. Published only while the app is on
    /// screen and at most every `routePublishInterval`, so a background walk
    /// doesn't redraw the map with every fix.
    /// Split where the GPS was silent over `routeGap`, so a gap is never
    /// drawn as a straight line through houses.
    @Published private(set) var todaysRoute: [[Coordinate]] = []
    private var routeBuffer: [[Coordinate]] = []
    private var lastRouteFix: Date?
    private static let routeGap: TimeInterval = 60
    private var routeDay = Calendar.current.startOfDay(for: Date())
    private var lastRoutePublish = Date.distantPast
    private static let routeSpacing: Double = 5
    private static let routePublishInterval: TimeInterval = 5
    /// Every walk anywhere in the world, newest first.
    @Published private(set) var walks: [Walk] = []
    @Published private(set) var walkMeta: [String: WalkMeta] = [:]
    /// Streets marked as walked by hand (long press on the map).
    @Published private(set) var manualStreets: Set<String> = []
    /// Name of the Obsidian folder, nil until one is picked.
    @Published private(set) var obsidianFolderName: String?
    /// One line about the last export / backup / import, for the settings.
    @Published private(set) var dataStatus: String?
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
    private let walkLibrary = WalkLibrary()
    private let obsidian = ObsidianExport()
    private var lastWalkSync = Date.distantPast
    /// While walking, refresh walks and the Obsidian notes this often.
    private static let walkSyncInterval: TimeInterval = 5 * 60
    /// Remembered so tracking continues by itself if iOS ended the app
    /// mid-walk and it gets opened again.
    private static let trackingKey = "trackingOn"
    private static let modeKey = "trackingMode"
    private var cancellables: Set<AnyCancellable> = []
    /// Launched with `-demo` (UI tests, screenshots): no real location, a
    /// made-up walk through Old Town is played in instead.
    let isDemo: Bool

    init(launchedForLocation: Bool = false, demo: Bool = false) {
        self.isDemo = demo
        let persistence = CoveragePersistence()
        let savedCounts = persistence.loadPassCounts()

        self.persistence = persistence
        self.coverageStore = CoverageStore(passCounts: savedCounts)
        self.passCounts = savedCounts
        self.locationTracker = LocationTracker()
        let mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(PowerPolicy.Mode.init(rawValue:)) ?? .precise
        self.mode = mode
        self.powerPolicy = PowerPolicy(mode: mode)
        let savedRoute = trackLog.todaysRoute(maxAccuracy: Self.matchAccuracy, gap: Self.routeGap).map { piece in
            piece.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        }
        self.routeBuffer = savedRoute.map(Self.thinned)
        self.todaysRoute = routeBuffer
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
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.publishRoute(force: true)
                self?.syncWalks()
            }
            .store(in: &cancellables)

        if !demo, UserDefaults.standard.bool(forKey: Self.trackingKey) {
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
            if demo { playDemoWalk() }
            syncWalks()
        }
        walkMeta = walkLibrary.loadMeta()
        manualStreets = walkLibrary.loadManualStreets()
        obsidianFolderName = obsidian.folder?.lastPathComponent
    }

    // MARK: Walks, Obsidian, backup, import (E2)

    /// Re-reads the walks and writes changed notes to Obsidian, off the
    /// main thread.
    func syncWalks() {
        lastWalkSync = Date()
        let library = walkLibrary
        let obsidian = obsidian
        let meta = walkMeta
        Task {
            let (walks, written) = await Task.detached(priority: .utility) {
                let walks = library.loadWalks()
                let edited = walks.compactMap { $0.applying(meta[$0.id]?.edit) }
                return (walks, obsidian.export(edited, meta: meta))
            }.value
            self.walks = walks
            if let written, written > 0 {
                self.dataStatus = "Do Obsidianu zapsáno: \(written) procházek"
                self.trackLog.appendEvent("obsidian", "zapsáno \(written)")
            }
        }
    }

    func chooseObsidianFolder(_ url: URL) {
        if obsidian.remember(url) {
            obsidianFolderName = url.lastPathComponent
            dataStatus = "Složka nastavená, zapisuju procházky…"
            syncWalks()
        } else {
            dataStatus = "Do složky se nedá zapisovat, zkus jinou."
        }
    }

    func forgetObsidianFolder() {
        obsidian.forget()
        obsidianFolderName = nil
    }

    func updateMeta(_ meta: WalkMeta, for walkID: String) {
        let editChanged = walkMeta[walkID]?.edit != meta.edit
        walkMeta[walkID] = meta
        walkLibrary.saveMeta(walkMeta)
        syncWalks()
        if editChanged { rebuildCoverage() }
    }

    // MARK: Editing walks and streets (E3)

    /// The walk as the person edited it; nil when all of it was removed.
    func edited(_ walk: Walk) -> Walk? {
        walk.applying(walkMeta[walk.id]?.edit)
    }

    /// Every tag in use, for filtering and suggestions.
    var allTags: [String] {
        Array(Set(walkMeta.values.flatMap(\.tags))).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    /// For snapping a finger-drawn piece to streets (nil while loading).
    var streetMatcher: MapMatcher? { matcher }

    func street(near coordinate: Coordinate) -> StreetSegment? {
        matcher?.match(coordinate).flatMap { graph.segments[$0.segmentID] }
    }

    /// "Tuhle ulici jsem prošel" and back.
    func toggleManual(_ segmentID: String) {
        if manualStreets.contains(segmentID) {
            manualStreets.remove(segmentID)
        } else {
            manualStreets.insert(segmentID)
        }
        walkLibrary.saveManualStreets(manualStreets)
        trackLog.appendEvent("rucne", segmentID)
        rebuildCoverage()
    }

    /// Recomputes pass counts from every logged fix, the walk edits, the
    /// streets marked by hand and the passes from before the log.
    func rebuildCoverage() {
        guard let matcher else { return }
        let library = walkLibrary, graph = graph, meta = walkMeta, manual = manualStreets
        let current = coverageStore.passCounts
        Task {
            let counts = await Task.detached(priority: .userInitiated) { () -> [String: Int] in
                let fixes = library.loadFixes()
                let legacy = library.loadLegacy() ?? {
                    let fromLog = CoverageRebuild.passCounts(fixes: fixes, graph: graph, matcher: matcher)
                    let legacy = CoverageRebuild.legacyCounts(current: current, fromLog: fromLog)
                    library.saveLegacy(legacy)
                    return legacy
                }()
                let walks = WalkSplitter.walks(from: fixes)
                let edits = walks.compactMap { walk in meta[walk.id]?.edit.map { (walk, $0) } }
                return CoverageRebuild.passCounts(
                    fixes: fixes,
                    excluded: edits.flatMap { $0.1.excludedRanges(of: $0.0) },
                    drawn: edits.flatMap { $0.1.drawn },
                    manualSegments: manual,
                    legacy: legacy,
                    graph: graph,
                    matcher: matcher
                )
            }.value
            coverageStore.replacePassCounts(counts)
            passCounts = counts
            coverageSummary = CoverageSummary(graph: graph, passCounts: counts)
            publishCoverage()
            persistence.savePassCounts(counts)
            trackLog.appendEvent("prepocet", "ulic s průchodem: \(counts.count)")
            refreshSuggestions()
        }
    }

    func backup() {
        let files = walkLibrary.csvFiles + [persistence.fileURL, walkLibrary.metaFile,
                                            walkLibrary.manualFile, walkLibrary.legacyFile]
        dataStatus = obsidian.backup(files: files)
            ? "Záloha uložená do složky zaloha"
            : "Zálohu se nepovedlo uložit, vyber složku Obsidianu znovu."
        trackLog.appendEvent("zaloha", dataStatus ?? "")
    }

    /// From a `zaloha` folder the person picked. Pass counts are merged
    /// (the higher count wins), so restoring never loses newer walks.
    func restore(from folder: URL) {
        let current = coverageStore.passCounts
        let restored = ObsidianExport.restore(from: folder) { name in
            switch name {
            case "coverage.json": return persistence.fileURL
            case "walk-meta.json": return walkLibrary.metaFile
            case "rucne-prosle-ulice.json": return walkLibrary.manualFile
            case "pokryti-pred-csv.json": return walkLibrary.legacyFile
            default:
                guard name.hasSuffix(".csv") else { return nil }
                return walkLibrary.trasyDir.appendingPathComponent(name)
            }
        }
        var merged = persistence.loadPassCounts()
        merged.merge(current) { max($0, $1) }
        coverageStore.replacePassCounts(merged)
        persistence.savePassCounts(merged)
        passCounts = merged
        coverageSummary = CoverageSummary(graph: graph, passCounts: merged)
        publishCoverage()
        walkMeta = walkLibrary.loadMeta()
        manualStreets = walkLibrary.loadManualStreets()
        dataStatus = "Obnoveno souborů: \(restored)"
        trackLog.appendEvent("obnova", dataStatus ?? "")
        syncWalks()
    }

    /// A GPX from Strava, Garmin... joins the walks and counts its streets.
    func importGPX(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            dataStatus = "Soubor se nedá otevřít."
            return
        }
        let fixes = walkLibrary.importGPX(data, name: url.lastPathComponent, fallback: Date())
        var newPasses = 0
        for fix in fixes {
            guard let match = matcher?.match(fix.coordinate) else { continue }
            let length = graph.segments[match.segmentID]?.lengthMeters ?? .infinity
            if coverageStore.recordFix(on: match.segmentID, at: fix.time, segmentLengthMeters: length) {
                coverageSummary.markWalked(match.segmentID)
                newPasses += 1
            }
        }
        passCounts = coverageStore.passCounts
        publishCoverage()
        persistence.savePassCounts(coverageStore.passCounts)
        dataStatus = fixes.isEmpty ? "V souboru není žádná trasa." : "Importováno \(fixes.count) bodů, průchodů ulicí: \(newPasses)"
        trackLog.appendEvent("import", "\(url.lastPathComponent): \(dataStatus ?? "")")
        syncWalks()
    }

    private func playDemoWalk() {
        let route = DemoWalk.route(in: graph)
        let start = Date().addingTimeInterval(-3 * Double(route.count))
        for (i, coord) in route.enumerated() {
            handle(location: CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
                course: -1, speed: 1.3, timestamp: start.addingTimeInterval(3 * Double(i))
            ))
        }
        isTracking = true
        publishRoute(force: true)
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
        guard !isDemo else { return }
        locationTracker.requestAuthorization()
    }

    func toggleTracking() {
        if isDemo {
            isTracking.toggle()
            return
        }
        if locationTracker.isTracking {
            locationTracker.stopTracking()
            motionMonitor.stop()
            isTracking = false
            UserDefaults.standard.set(false, forKey: Self.trackingKey)
            trackLog.appendEvent("sber", "zastaveno")
            syncWalks()
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
        // While Core Motion still confidently says "vehicle" (a tram or car
        // crawling in traffic), the pace has to hold much longer to count.
        let inVehicle = motionMonitor.activity == .vehicle
        let pacedWalking = speedDetector.isWalking(at: now, inVehicle: inVehicle)
        if pacedWalking {
            // Core Motion can lag minutes behind after a ride; a steady
            // walking pace is enough to leave saving mode.
            powerPolicy.update(.walking, at: now)
        }
        // The delayed re-check below may not run while iOS suspends the app
        // between fixes, so re-evaluate on every fix too.
        let lowPower = applyPowerMode(at: now)

        let isAccurate = location.horizontalAccuracy >= 0 && location.horizontalAccuracy < Self.matchAccuracy
        let coord = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let walking = motionMonitor.isLikelyWalking || pacedWalking
        // Saving mode only thins street matching and the map; every fix
        // still goes to the log.
        let process = !lowPower || lastProcessedFix.map { now.timeIntervalSince($0) >= Self.lowPowerInterval } ?? true

        // Log every fix (walking or not, accurate or not) before any
        // filtering, so the whole route with exact times survives and can be
        // recomputed if matching rules change.
        let matched = process && isAccurate ? matcher?.match(coord) : nil
        let segment = matched.flatMap { graph.segments[$0.segmentID] }
        trackLog.append(
            location,
            isWalking: walking,
            street: segment.map { TrackLog.StreetInfo(name: $0.name, district: $0.district) }
        )
        loggedPoints += 1
        guard process else { return }
        lastProcessedFix = now
        guard isAccurate else { return }
        lastLocation = coord
        addToRoute(coord, at: now)

        if now.timeIntervalSince(lastWalkSync) >= Self.walkSyncInterval {
            syncWalks()
        }

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

    private func addToRoute(_ coord: Coordinate, at time: Date) {
        let day = Calendar.current.startOfDay(for: time)
        if day != routeDay {
            // A new day starts a new CSV, so the map starts over too.
            routeDay = day
            routeBuffer = []
        }
        defer { lastRouteFix = time }
        if routeBuffer.isEmpty || lastRouteFix.map({ time.timeIntervalSince($0) > Self.routeGap }) ?? true {
            routeBuffer.append([coord])
        } else {
            if let last = routeBuffer[routeBuffer.count - 1].last, Geo.distance(last, coord) < Self.routeSpacing { return }
            routeBuffer[routeBuffer.count - 1].append(coord)
        }
        publishRoute(force: false)
    }

    private func publishRoute(force: Bool) {
        guard UIApplication.shared.applicationState == .active else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastRoutePublish) >= Self.routePublishInterval else { return }
        lastRoutePublish = now
        if routeDay != Calendar.current.startOfDay(for: now) {
            routeDay = Calendar.current.startOfDay(for: now)
            routeBuffer = []
        }
        if todaysRoute.map(\.count) != routeBuffer.map(\.count) {
            todaysRoute = routeBuffer
        }
    }

    private static func thinned(_ route: [Coordinate]) -> [Coordinate] {
        var result: [Coordinate] = []
        for coord in route where result.last.map({ Geo.distance($0, coord) >= routeSpacing }) ?? true {
            result.append(coord)
        }
        return result
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
    private func applyPowerMode(at time: Date = Date()) -> Bool {
        let lowPower = powerPolicy.isLowPower(at: time)
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
