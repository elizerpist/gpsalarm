import 'package:flutter/material.dart';
import '../services/geocoding_service.dart';

class SearchPill extends StatelessWidget {
  final void Function(GeocodingResult) onResultSelected;

  const SearchPill({super.key, required this.onResultSelected});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
