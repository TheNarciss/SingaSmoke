import MapKit
import SingaSmokeCore
import SwiftUI

/// MKMapView behind SwiftUI: native clustering for 4,000+ retailers and one overlay per
/// reliability level for thousands of no-smoking polygons, which SwiftUI's Map does not scale to.
struct SingaMapView: UIViewRepresentable {
    var spots: [SmokingSpot] = []
    var retailers: [Retailer] = []
    var zoneIndex: ZoneIndex?
    var marker: MarkerAnnotation?
    var route: MKPolyline?
    /// Follow the user with the compass (guidance) instead of letting them pan freely.
    var followsHeading = false
    /// Incremented by the parent to recentre on the user.
    var recenterToken = 0
    var onSelectSpot: (SmokingSpot) -> Void = { _ in }
    var onSelectRetailer: (Retailer) -> Void = { _ in }
    var onRegionChange: (MKCoordinateRegion) -> Void = { _ in }

    static let singapore = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198),
        latitudinalMeters: 30_000, longitudinalMeters: 42_000
    )

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        // A quiet, desaturated basemap without points of interest, so the zones and markers carry the map.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        map.preferredConfiguration = configuration
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = false
        map.register(BadgeAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.spotID)
        map.register(BadgeAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.retailerID)
        map.register(BadgeAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.markerID)
        map.register(BadgeAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.setRegion(Self.singapore, animated: false)
        map.setCameraBoundary(MKMapView.CameraBoundary(coordinateRegion: MKCoordinateRegion(
            center: Self.singapore.center, latitudinalMeters: 70_000, longitudinalMeters: 90_000)), animated: false)
        map.setCameraZoomRange(MKMapView.CameraZoomRange(maxCenterCoordinateDistance: 120_000), animated: false)
        if followsHeading { map.setUserTrackingMode(.followWithHeading, animated: false) }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        static let spotID = "spot"
        static let retailerID = "retailer"
        static let markerID = "marker"

        var parent: SingaMapView
        private var spotIDs: [String] = []
        private var retailerIDs: Set<String> = []
        private var retailerAnnotations: [String: RetailerAnnotation] = [:]
        private var shownMarker: MarkerAnnotation?
        private var shownRoute: MKPolyline?
        private var recenterToken = 0
        private var centeredOnUser = false
        private var zoneOverlays: [ZoneOverlay] = []
        private var zonesEnabled = false
        private var zoneSignature = 0
        private var polygonCache: [String: [MKPolygon]] = [:]

        init(parent: SingaMapView) {
            self.parent = parent
        }

        // MARK: Keeping MapKit in step with SwiftUI

        func sync(_ map: MKMapView) {
            syncSpots(map)
            syncRetailers(map)
            syncMarker(map)
            syncRoute(map)
            // The zones only change with the map region (handled in regionDidChange), except when
            // the data arrives or goes: SwiftUI calls sync on every state change, keep it cheap.
            if (parent.zoneIndex != nil) != zonesEnabled {
                zonesEnabled = parent.zoneIndex != nil
                zoneSignature = 0
                refreshZones(map)
            }
            if parent.recenterToken != recenterToken {
                recenterToken = parent.recenterToken
                map.setUserTrackingMode(parent.followsHeading ? .followWithHeading : .follow, animated: true)
            }
        }

        private func syncSpots(_ map: MKMapView) {
            let ids = parent.spots.map(\.id)
            guard ids != spotIDs else { return }
            map.removeAnnotations(map.annotations.filter { $0 is SpotAnnotation })
            map.addAnnotations(parent.spots.map(SpotAnnotation.init))
            spotIDs = ids
        }

        private func syncRetailers(_ map: MKMapView) {
            let wanted = Dictionary(parent.retailers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let wantedIDs = Set(wanted.keys)
            guard wantedIDs != retailerIDs else { return }
            let removed = retailerIDs.subtracting(wantedIDs).compactMap { retailerAnnotations.removeValue(forKey: $0) }
            let added = wantedIDs.subtracting(retailerIDs).compactMap { id -> RetailerAnnotation? in
                guard let retailer = wanted[id] else { return nil }
                let annotation = RetailerAnnotation(retailer)
                retailerAnnotations[id] = annotation
                return annotation
            }
            map.removeAnnotations(removed)
            map.addAnnotations(added)
            retailerIDs = wantedIDs
        }

        private func syncMarker(_ map: MKMapView) {
            let wanted = parent.marker
            guard wanted?.coordinate.latitude != shownMarker?.coordinate.latitude
                || wanted?.coordinate.longitude != shownMarker?.coordinate.longitude
                || wanted?.title != shownMarker?.title else { return }
            if let shownMarker { map.removeAnnotation(shownMarker) }
            if let wanted { map.addAnnotation(wanted) }
            shownMarker = wanted
        }

        private func syncRoute(_ map: MKMapView) {
            guard parent.route !== shownRoute else { return }
            if let shownRoute { map.removeOverlay(shownRoute) }
            if let route = parent.route { map.addOverlay(route, level: .aboveRoads) }
            shownRoute = parent.route
        }

        /// Large zones (parks, Orchard, schools…) at every zoom; small ones (bus stops,
        /// playgrounds, courts…) only once zoomed in, where they are readable.
        private func refreshZones(_ map: MKMapView) {
            guard let index = parent.zoneIndex else {
                if !zoneOverlays.isEmpty { map.removeOverlays(zoneOverlays); zoneOverlays = [] }
                return
            }
            let region = map.region
            let showSmall = region.span.latitudeDelta < 0.03
            var visible = index.zones(in: BoundingBox(region, padding: 0.25))
            if !showSmall { visible = visible.filter { $0.kind.isLarge } }
            if visible.count > 6_000 { visible = Array(visible.prefix(6_000)) }

            var hasher = Hasher()
            for zone in visible { hasher.combine(zone.id) }
            let signature = hasher.finalize()
            guard signature != zoneSignature else { return }
            zoneSignature = signature

            var official: [MKPolygon] = []
            var indicative: [MKPolygon] = []
            for zone in visible {
                let shapes: [MKPolygon]
                if let cached = polygonCache[zone.id] {
                    shapes = cached
                } else {
                    shapes = ZoneShapes.polygons(for: zone)
                    polygonCache[zone.id] = shapes
                }
                if zone.reliability == .official { official += shapes } else { indicative += shapes }
            }
            var overlays: [ZoneOverlay] = []
            if !indicative.isEmpty {
                let overlay = ZoneOverlay(indicative)
                overlay.isOfficial = false
                overlays.append(overlay)
            }
            if !official.isEmpty {
                overlays.append(ZoneOverlay(official))
            }
            map.removeOverlays(zoneOverlays)
            map.addOverlays(overlays, level: .aboveRoads)
            zoneOverlays = overlays
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            refreshZones(mapView)
            parent.onRegionChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            // First fix in Singapore: zoom onto the user, once.
            guard !centeredOnUser, !parent.followsHeading, let location = userLocation.location,
                  Geo.singapore.contains(Coordinate(location.coordinate)) else { return }
            centeredOnUser = true
            mapView.setRegion(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 900, longitudinalMeters: 900),
                              animated: true)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKUserLocation:
                return nil
            case let spot as SpotAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.spotID, for: spot)
                view.image = MapBadge.spot(spot.spot)
                view.displayPriority = spot.spot.reliability == .official ? .defaultHigh : .defaultLow
                view.clusteringIdentifier = Self.spotID   // Orchard's yellow boxes merge when zoomed out
                view.zPriority = .max
                view.accessibilityLabel = "\(spot.spot.name), \(spot.spot.source.label)"
                return view
            case let shop as RetailerAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.retailerID, for: shop)
                view.image = MapBadge.retailer(shop.retailer)
                view.clusteringIdentifier = "retailer"
                view.displayPriority = .defaultLow
                view.accessibilityLabel = "\(shop.retailer.name), \(shop.retailer.category.label)"
                return view
            case let cluster as MKClusterAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster)
                let count = cluster.memberAnnotations.count
                let spots = cluster.memberAnnotations.first is SpotAnnotation
                view.image = MapBadge.cluster(count: count, fill: spots ? Brand.allowedUI : MapBadge.ink)
                view.displayPriority = spots ? .required : .defaultHigh
                view.zPriority = spots ? .max : .defaultUnselected
                view.accessibilityLabel = spots ? "\(count) smoking spots" : "\(count) shops"
                return view
            case let marker as MarkerAnnotation:
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.markerID, for: marker)
                view.image = marker.style == .exit ? MapBadge.exit() : MapBadge.destination()
                view.displayPriority = .required
                view.clusteringIdentifier = nil
                view.zPriority = .max
                view.accessibilityLabel = marker.title
                return view
            default:
                return nil
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let zone = overlay as? ZoneOverlay {
                let renderer = MKMultiPolygonRenderer(multiPolygon: zone)
                renderer.fillColor = Brand.dangerUI.withAlphaComponent(zone.isOfficial ? 0.20 : 0.12)
                renderer.strokeColor = Brand.dangerUI.withAlphaComponent(zone.isOfficial ? 0.95 : 0.7)
                renderer.lineWidth = zone.isOfficial ? 2 : 1.5
                if !zone.isOfficial { renderer.lineDashPattern = [5, 4] }
                return renderer
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = Brand.allowedUI
                renderer.lineWidth = 7
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            switch annotation {
            case let spot as SpotAnnotation:
                parent.onSelectSpot(spot.spot)
                mapView.deselectAnnotation(annotation, animated: false)
            case let shop as RetailerAnnotation:
                parent.onSelectRetailer(shop.retailer)
                mapView.deselectAnnotation(annotation, animated: false)
            case let cluster as MKClusterAnnotation:
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                mapView.deselectAnnotation(annotation, animated: false)
            default:
                break
            }
        }
    }
}
