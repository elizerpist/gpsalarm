import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/map_provider.dart';
import '../services/geocoding_service.dart';

class SearchPill extends StatefulWidget {
  final void Function(GeocodingResult) onResultSelected;

  const SearchPill({super.key, required this.onResultSelected});

  @override
  State<SearchPill> createState() => _SearchPillState();
}

class _SearchPillState extends State<SearchPill> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapProv = context.watch<MapProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: 90,
      left: 16,
      right: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.search, color: Colors.grey[500], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: tr('search_city'),
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey[400]),
                    ),
                    onChanged: (query) => mapProv.search(query),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _controller.clear();
                      mapProv.search('');
                    },
                    child:
                        Icon(Icons.close, color: Colors.grey[400], size: 20),
                  ),
                const SizedBox(width: 12),
              ],
            ),
          ),
          if (mapProv.searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: mapProv.searchResults.map((result) {
                  return InkWell(
                    onTap: () => widget.onResultSelected(result),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 18, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(result.displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                if (result.country != null)
                                  Text(
                                    [result.city, result.country]
                                        .whereType<String>()
                                        .join(', '),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500]),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          if (mapProv.searchError != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                tr(mapProv.searchError!),
                style: TextStyle(color: Colors.red[400], fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
