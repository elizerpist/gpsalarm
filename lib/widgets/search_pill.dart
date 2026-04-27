import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/map_provider.dart';
import '../services/geocoding_service.dart';

/// Search pill that expands from the FAB position (bottom-right) to the left.
/// Sits at the same height as the FAB (bottom: 24).
class SearchPill extends StatefulWidget {
  final void Function(GeocodingResult) onResultSelected;
  final VoidCallback? onClose;

  const SearchPill({super.key, required this.onResultSelected, this.onClose});

  @override
  State<SearchPill> createState() => _SearchPillState();
}

class _SearchPillState extends State<SearchPill> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() => setState(() {}));
    _expandAnim = CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
    _expandCtrl.forward();
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapProv = context.watch<MapProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenWidth = MediaQuery.of(context).size.width;

    // FAB: 56px wide, right: 16. Collapsed = FAB left edge. Expanded = left: 16.
    final collapsedLeft = screenWidth - 56 - 16;
    const expandedLeft = 16.0;
    final left = collapsedLeft + (expandedLeft - collapsedLeft) * _expandAnim.value;

    return Positioned(
      bottom: 24 + keyboardHeight,
      left: left,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Input bar — same height as FAB (56px)
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.circular(16),
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
                  child: Opacity(
                    opacity: _expandAnim.value.clamp(0.3, 1.0),
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: tr('search_city'),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        isDense: false,
                        hintStyle: TextStyle(color: Colors.grey[400]),
                      ),
                      onChanged: (query) => mapProv.search(query),
                    ),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _controller.clear();
                      mapProv.search('');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.close, color: Colors.grey[400], size: 20),
                    ),
                  ),
                // Close search button (takes FAB's place)
                GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF5252), Color(0xFFC62828)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          // Results dropdown
          if (mapProv.searchResults.isNotEmpty && _expandAnim.value > 0.8)
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
