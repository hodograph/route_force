import 'package:flutter/material.dart';
import '../enums/travel_mode.dart';

class TravelModeButton extends StatelessWidget {
  final IconData icon;
  final TravelMode mode;
  final TravelMode currentMode;
  final VoidCallback onTap;

  const TravelModeButton({
    super.key,
    required this.icon,
    required this.mode,
    required this.currentMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = mode == currentMode;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color:
              isSelected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
