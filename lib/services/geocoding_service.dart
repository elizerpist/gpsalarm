import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingResult {
  final String displayName;
  final String? city;
  final String? country;
  final double latitude;
  final double longitude;

  GeocodingResult({
    required this.displayName,
    this.city,
    this.country,
    required this.latitude,
    required this.longitude,
  });
}

class GeocodingService {
  static const String _baseUrl = 'https://photon.komoot.io/api/';
  static const Duration _debounce = Duration(milliseconds: 300);

  Timer? _debounceTimer;

  void search(String query, void Function(List<GeocodingResult>) onResults,
      void Function(String) onError) {
    _debounceTimer?.cancel();
    if (query.trim().length < 2) {
      onResults([]);
      return;
    }
    _debounceTimer = Timer(_debounce, () async {
      try {
        final uri = Uri.parse(
            '$_baseUrl?q=${Uri.encodeComponent(query)}&limit=5&lang=hu');
        final response = await http.get(uri, headers: {
          'User-Agent': 'GPSAlarmApp/1.0',
        });
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final features = data['features'] as List;
          final results = features.map((f) {
            final props = f['properties'];
            final coords = f['geometry']['coordinates'];
            return GeocodingResult(
              displayName: props['name'] ?? '',
              city: props['city'] as String?,
              country: props['country'] as String?,
              latitude: (coords[1] as num).toDouble(),
              longitude: (coords[0] as num).toDouble(),
            );
          }).toList();
          onResults(results);
        } else {
          onError('connection_error');
        }
      } catch (e) {
        onError('connection_error');
      }
    });
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}
