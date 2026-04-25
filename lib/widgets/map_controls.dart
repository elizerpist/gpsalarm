import 'package:flutter/material.dart';

class MapControls extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onSearchTap;
  final VoidCallback onMyLocation;
  final bool searchActive;

  const MapControls({
    super.key,
    required this.onMenuTap,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onSearchTap,
    required this.onMyLocation,
    required this.searchActive,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? Colors.grey[900]!.withOpacity(0.92)
        : Colors.white.withOpacity(0.92);
    final iconColor = isDark ? Colors.white : Colors.grey[800]!;

    return Stack(
      children: [
        // Hamburger - top left
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 12,
          child: _ControlButton(
            onTap: onMenuTap,
            bgColor: bgColor,
            child: Icon(Icons.menu, color: iconColor, size: 24),
          ),
        ),
        // Zoom buttons - right side above FAB
        Positioned(
          bottom: 140,
          right: 16,
          child: Column(
            children: [
              _ControlButton(
                onTap: onZoomIn,
                bgColor: bgColor,
                child: Icon(Icons.add, color: iconColor, size: 24),
              ),
              const SizedBox(height: 4),
              _ControlButton(
                onTap: onZoomOut,
                bgColor: bgColor,
                child: Icon(Icons.remove, color: iconColor, size: 24),
              ),
            ],
          ),
        ),
        // My location button
        Positioned(
          bottom: 92,
          right: 16,
          child: _ControlButton(
            onTap: onMyLocation,
            bgColor: bgColor,
            child: Icon(Icons.my_location, color: iconColor, size: 22),
          ),
        ),
        // FAB - bottom right
        Positioned(
          bottom: 24,
          right: 16,
          child: GestureDetector(
            onTap: onSearchTap,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: searchActive
                      ? [Colors.red[400]!, Colors.red[800]!]
                      : [Colors.blue[400]!, Colors.blue[800]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (searchActive ? Colors.red : Colors.blue)
                        .withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                searchActive ? Icons.close : Icons.search,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color bgColor;
  final Widget child;

  const _ControlButton({
    required this.onTap,
    required this.bgColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}
