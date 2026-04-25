import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../services/geocoding_service.dart';

class MapProvider extends ChangeNotifier {
  LatLng _center = const LatLng(47.4979, 19.0402); // Budapest default
  double _zoom = 13.0;
  bool _searchActive = false;
  List<GeocodingResult> _searchResults = [];
  String? _searchError;

  final GeocodingService _geocodingService = GeocodingService();

  LatLng get center => _center;
  double get zoom => _zoom;
  bool get searchActive => _searchActive;
  List<GeocodingResult> get searchResults => _searchResults;
  String? get searchError => _searchError;

  void setCenter(LatLng center) {
    _center = center;
    notifyListeners();
  }

  void setZoom(double zoom) {
    _zoom = zoom.clamp(3.0, 18.0);
    notifyListeners();
  }

  void zoomIn() => setZoom(_zoom + 1);
  void zoomOut() => setZoom(_zoom - 1);

  void toggleSearch() {
    _searchActive = !_searchActive;
    if (!_searchActive) {
      _searchResults = [];
      _searchError = null;
    }
    notifyListeners();
  }

  void search(String query) {
    _searchError = null;
    _geocodingService.search(
      query,
      (results) {
        _searchResults = results;
        _searchError = null;
        notifyListeners();
      },
      (error) {
        _searchResults = [];
        _searchError = error;
        notifyListeners();
      },
    );
  }

  void goToSearchResult(GeocodingResult result) {
    _center = LatLng(result.latitude, result.longitude);
    _zoom = 14.0;
    _searchActive = false;
    _searchResults = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _geocodingService.dispose();
    super.dispose();
  }
}
