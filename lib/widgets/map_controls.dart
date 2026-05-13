import 'package:flutter/material.dart';

class MapControls extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onSearchTap;
  final VoidCallback onMyLocation;
  final bool searchActive;
  final VoidCallback? onMapToggleTap;
  final IconData? iconMapToggle;
  final VoidCallback? onSkinTap;
  final IconData? iconSkin;
  final IconData? myLocationIcon;
  final Color? myLocationIconColor;
  final Color? myLocationBgColor;
  final VoidCallback? onMyLocationLongPress;
  // 3D button (vector map only)
  final VoidCallback? on3DTap;
  final VoidCallback? on3DLongPress;
  final IconData? icon3D;
  final Color? icon3DColor;
  final Color? bg3DColor;
  // Freeze button (ejects from 3D when active)
  final VoidCallback? onFreezeTap;
  final IconData? iconFreeze;
  final Color? iconFreezeColor;
  final Color? bgFreezeColor;
  final bool showFreeze;

  const MapControls({
    super.key,
    required this.onMenuTap,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onSearchTap,
    required this.onMyLocation,
    required this.searchActive,
    this.onMapToggleTap,
    this.iconMapToggle,
    this.onSkinTap,
    this.iconSkin,
    this.myLocationIcon,
    this.myLocationIconColor,
    this.myLocationBgColor,
    this.onMyLocationLongPress,
    this.on3DTap,
    this.on3DLongPress,
    this.icon3D,
    this.icon3DColor,
    this.bg3DColor,
    this.onFreezeTap,
    this.iconFreeze,
    this.iconFreezeColor,
    this.bgFreezeColor,
    this.showFreeze = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? Colors.grey[900]!.withOpacity(0.92)
        : Colors.white.withOpacity(0.92);
    final iconColor = isDark ? Colors.white : Colors.grey[800]!;

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

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
        // Map tools + zoom buttons - right side above FAB
        Positioned(
          bottom: 140 + keyboardHeight,
          right: 16,
          child: Column(
            children: [
              if (on3DTap != null) ...[
                SizedBox(
                  height: 52,
                  child: IgnorePointer(
                    ignoring: !showFreeze || onFreezeTap == null,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      offset: showFreeze ? Offset.zero : const Offset(0, 0.35),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 140),
                        opacity: showFreeze && onFreezeTap != null ? 1 : 0,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ControlButton(
                            onTap: onFreezeTap ?? () {},
                            bgColor: bgFreezeColor ?? bgColor,
                            child: Icon(
                              iconFreeze ?? Icons.screen_rotation_alt,
                              color: iconFreezeColor ?? iconColor,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ControlButton(
                    onTap: on3DTap!,
                    bgColor: bg3DColor ?? bgColor,
                    child: Icon(
                      icon3D ?? Icons.threed_rotation,
                      color: icon3DColor ?? iconColor,
                      size: 22,
                    ),
                  ),
                ),
              ],
              if (onSkinTap != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ControlButton(
                    onTap: onSkinTap!,
                    bgColor: bgColor,
                    child: Icon(
                      iconSkin ?? Icons.palette,
                      color: iconColor,
                      size: 22,
                    ),
                  ),
                ),
              if (onMapToggleTap != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ControlButton(
                    onTap: onMapToggleTap!,
                    bgColor: bgColor,
                    child: Icon(
                      iconMapToggle ?? Icons.layers,
                      color: iconColor,
                      size: 22,
                    ),
                  ),
                ),
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
        // My location / 3D toggle button
        Positioned(
          bottom: 92 + keyboardHeight,
          right: 16,
          child: GestureDetector(
            onTap: onMyLocation,
            onLongPress: onMyLocationLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: myLocationBgColor ?? bgColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    myLocationIcon ?? Icons.my_location,
                    key: ValueKey(myLocationIcon ?? Icons.my_location),
                    color: myLocationIconColor ?? iconColor,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
        // FAB - bottom right (hidden when search is active — pill takes over)
        if (!searchActive)
          Positioned(
            bottom: 24 + keyboardHeight,
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
                        : [const Color(0xFF3FA2FF), const Color(0xFF1F6FD1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (searchActive ? Colors.red : const Color(0xFF3FA2FF))
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
