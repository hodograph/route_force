import 'package:flutter/material.dart';
import 'package:route_force/enums/distance_unit.dart'; // Import DistanceUnit
import 'package:route_force/utils/distance_utils.dart'; // Import DistanceUtils

class DirectionsList extends StatelessWidget {
  final List<dynamic> steps;
  final IconData Function(String maneuver) getManeuverIconData;
  final IconData Function(String? vehicleType) getTransitVehicleIcon;
  final String Function(String htmlString) stripHtmlIfNeeded;
  final Color primaryColor;
  final DistanceUnit currentDistanceUnit; // Added

  const DirectionsList({
    super.key,
    required this.steps,
    required this.getManeuverIconData,
    required this.getTransitVehicleIcon,
    required this.stripHtmlIfNeeded,
    required this.primaryColor,
    required this.currentDistanceUnit, // Added
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? secondaryTextColor = theme.textTheme.bodyMedium?.color
        ?.withValues(alpha: 0.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Directions to this stop:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...steps.map((step) {
          String instruction = step['html_instructions'] ?? 'No instruction';
          // Assuming step structure from Google Directions API or similar
          int distanceValueInMeters = step['distance'] as int? ?? 0;
          String formattedDistanceText = DistanceUtils.formatDistance(
            distanceValueInMeters,
            currentDistanceUnit,
          );
          String durationText =
              step['durationText'] as String? ??
              ''; // Expect durationText from CF
          String maneuver = step['maneuver'] ?? '';
          Map? transitDetails = step['transit_details'] as Map?;

          List<Widget> stepWidgets = [];

          stepWidgets.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  getManeuverIconData(maneuver),
                  size: 24.0,
                  color: primaryColor,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stripHtmlIfNeeded(instruction),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (formattedDistanceText.isNotEmpty ||
                          durationText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            '$formattedDistanceText${formattedDistanceText.isNotEmpty && durationText.isNotEmpty ? "  •  " : ""}$durationText',
                            style: TextStyle(
                              fontSize: 14,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );

          if (transitDetails != null) {
            final line = transitDetails['line'] as Map?;
            final vehicle = line?['vehicle'] as Map?;
            final departureStop = transitDetails['departure_stop'] as Map?;
            final arrivalStop = transitDetails['arrival_stop'] as Map?;
            final headsign = transitDetails['headsign'] as String?;
            final numStops = transitDetails['num_stops'] as int?;

            String lineName = line?['name'] ?? line?['short_name'] ?? '';
            String vehicleName = vehicle?['name'] ?? '';

            stepWidgets.add(
              Padding(
                padding: const EdgeInsets.only(
                  left: 40.0,
                  top: 6.0,
                  bottom: 4.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (vehicleName.isNotEmpty || lineName.isNotEmpty)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Builder(
                            builder: (context) {
                              Widget iconWidget;
                              final String? vehicleIconUrl =
                                  vehicle?['icon'] as String?;
                              if (vehicleIconUrl != null &&
                                  vehicleIconUrl.startsWith('https://')) {
                                iconWidget = Image.network(
                                  vehicleIconUrl,
                                  height: 20, // Slightly larger for clarity
                                  width: 20,
                                  errorBuilder: (context, error, stackTrace) {
                                    // Fallback to IconData if image fails to load
                                    return Icon(
                                      getTransitVehicleIcon(
                                        vehicle?['type'] as String?,
                                      ),
                                      size: 18,
                                      color: theme.colorScheme.secondary,
                                    );
                                  },
                                );
                              } else {
                                iconWidget = Icon(
                                  getTransitVehicleIcon(
                                    vehicle?['type'] as String?,
                                  ),
                                  size: 18,
                                  color: theme.colorScheme.secondary,
                                );
                              }
                              return iconWidget;
                            },
                          ),
                          const SizedBox(width: 8), // Adjusted spacing
                          Expanded(
                            child: Text(
                              '${vehicleName.isNotEmpty ? "$vehicleName: " : ""}$lineName${headsign != null && headsign.isNotEmpty ? ' towards $headsign' : ''}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: theme.textTheme.titleSmall?.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (departureStop?['name'] != null &&
                        arrivalStop?['name'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3.0),
                        child: Text(
                          'From: ${departureStop!['name']}\nTo: ${arrivalStop!['name']}',
                          style: TextStyle(
                            fontSize: 13,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                    if (numStops != null && numStops > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 3.0),
                        child: Text(
                          '$numStops stop${numStops > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            color: secondaryTextColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: stepWidgets,
            ),
          );
        }),
      ],
    );
  }
}
