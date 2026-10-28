import SwiftUI
import MapKit
import StreetTrackerCore

/// All segments walked the same number of times, drawn as ONE overlay.
/// MapKit slows to a crawl with tens of thousands of individual overlays
/// (the full Prague graph is ~32k segments), so segments are grouped by
/// pass count instead; line width only changes up to `maxPassBucket`.
final class StreetMultiPolyline: MKMultiPolyline {
    var passCount: Int = 0
}

/// Today's recorded GPS route, drawn thin so gaps in street matching are
/// visible as "walked here, but not snapped".
final class RoutePolyline: MKPolyline {}

struct MapView: UIViewRepresentable {
    let graph: StreetGraph
    let passCounts: [String: Int]
    let route: [Coordinate]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        centerOnPrague(mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // SwiftUI calls this on every published change (each GPS fix, the
        // tracking toggle, ...); only rebuild overlays when the data changed.
        let coordinator = context.coordinator
        updateRoute(mapView, coordinator: coordinator)
        guard graph.segments.count != coordinator.segmentCount || passCounts != coordinator.passCounts else {
            return
        }
        if graph.segments.count != coordinator.segmentCount {
            coordinator.polylines = graph.segments.compactMapValues { segment in
                let coords = segment.points.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                guard coords.count >= 2 else { return nil }
                return MKPolyline(coordinates: coords, count: coords.count)
            }
            coordinator.segmentCount = graph.segments.count
        }
        coordinator.passCounts = passCounts

        var buckets: [Int: [MKPolyline]] = [:]
        for (id, polyline) in coordinator.polylines {
            let bucket = min(passCounts[id] ?? 0, Self.maxPassBucket)
            buckets[bucket, default: []].append(polyline)
        }
        mapView.removeOverlays(mapView.overlays.filter { $0 is StreetMultiPolyline })
        // Unwalked first so walked streets draw on top of them, all above
        // the raw route.
        for bucket in buckets.keys.sorted() {
            let overlay = StreetMultiPolyline(buckets[bucket]!)
            overlay.passCount = bucket
            mapView.addOverlay(overlay)
        }
    }

    private func updateRoute(_ mapView: MKMapView, coordinator: Coordinator) {
        guard route.count != coordinator.routeCount else { return }
        coordinator.routeCount = route.count
        if let old = coordinator.routeOverlay {
            mapView.removeOverlay(old)
        }
        guard route.count >= 2 else {
            coordinator.routeOverlay = nil
            return
        }
        let coords = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let overlay = RoutePolyline(coordinates: coords, count: coords.count)
        coordinator.routeOverlay = overlay
        mapView.insertOverlay(overlay, at: 0)
    }

    /// Line width stops growing at 7 passes (2 + 7 * 1.5 > 12 cap).
    static let maxPassBucket = 7

    private func centerOnPrague(_ mapView: MKMapView) {
        let center = CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378)
        let region = MKCoordinateRegion(center: center, latitudinalMeters: 3000, longitudinalMeters: 3000)
        mapView.setRegion(region, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var polylines: [String: MKPolyline] = [:]
        var segmentCount = -1
        var passCounts: [String: Int] = [:]
        var routeOverlay: RoutePolyline?
        var routeCount = -1

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let route = overlay as? RoutePolyline {
                let renderer = MKPolylineRenderer(polyline: route)
                renderer.strokeColor = UIColor.systemOrange
                renderer.lineWidth = 2
                return renderer
            }
            guard let multi = overlay as? StreetMultiPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKMultiPolylineRenderer(multiPolyline: multi)
            if multi.passCount == 0 {
                renderer.strokeColor = UIColor.systemGray3
                renderer.lineWidth = 1.5
            } else {
                renderer.strokeColor = UIColor.systemBlue
                // Thickens with each pass, capped so heavily-walked streets
                // don't swallow the map.
                renderer.lineWidth = min(2.0 + Double(multi.passCount) * 1.5, 12.0)
            }
            return renderer
        }
    }
}
