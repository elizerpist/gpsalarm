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
  static const String _nominatimUrl =
      'https://nominatim.openstreetmap.org/search';
  static const Duration _debounce = Duration(milliseconds: 400);

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
            '$_nominatimUrl?q=${Uri.encodeComponent(query)}&format=json&limit=5&accept-language=hu');
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as List;
          final results = data.map((item) {
            final displayName = item['display_name'] as String;
            final parts = displayName.split(', ');
            return GeocodingResult(
              displayName: parts.first,
              city: parts.length > 1 ? parts[1] : null,
              country: parts.length > 2 ? parts.last : null,
              latitude: double.parse(item['lat'] as String),
              longitude: double.parse(item['lon'] as String),
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
