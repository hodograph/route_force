import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:route_force/models/trip.dart';
import 'package:route_force/models/scheduled_stop_info.dart';
import 'package:route_force/models/route_info.dart';
import 'package:route_force/enums/travel_mode.dart' as travel_mode_enum;
import 'package:route_force/enums/distance_unit.dart'; // Import DistanceUnit
import 'package:route_force/utils/distance_utils.dart'; // Import DistanceUtils

class ItineraryExportWidget extends StatelessWidget {
  final Trip trip;
  final List<ScheduledStopInfo> scheduleDetails;
  final Map<String, RouteInfo>
  routes; // Changed from List<RouteInfo> to single RouteInfo
  final IconData Function(travel_mode_enum.TravelMode mode) getTravelModeIcon;
  final DistanceUnit currentDistanceUnit; // Added

  const ItineraryExportWidget({
    super.key,
    required this.trip,
    required this.scheduleDetails,
    required this.routes,
    required this.getTravelModeIcon,
    required this.currentDistanceUnit, // Added
  });

  String _getStopScheduleSummary(ScheduledStopInfo scheduledStop) {
    String arrivalStr = DateFormat('h:mm a').format(scheduledStop.arrivalTime);
    String departureStr = DateFormat(
      'h:mm a',
    ).format(scheduledStop.departureTime);
    String arrivalSuffix = scheduledStop.isArrivalManual ? " (M)" : "";
    String departureSuffix = scheduledStop.isDepartureManual ? " (M)" : "";
    return 'Arrival: $arrivalStr$arrivalSuffix | Depart: $departureStr$departureSuffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16.0),
      color:
          theme
              .scaffoldBackgroundColor, // Use scaffold background for the image
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trip.name,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Date: ${DateFormat('MMM dd, yyyy').format(trip.date)}',
            style: theme.textTheme.titleMedium,
          ),
          if (trip.description != null && trip.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Description: ${trip.description}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          Text(
            'Itinerary:',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (scheduleDetails.isEmpty)
            const Text('This trip has no stops.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: scheduleDetails.length,
              itemBuilder: (context, index) {
                final scheduledStop = scheduleDetails[index];
                final stop = scheduledStop.stop;

                RouteInfo? routeToThisStop;
                if (index > 0) {
                  final prevStop = scheduleDetails[index - 1].stop;
                  final routeId = '${prevStop.id}-${stop.id}';
                  routeToThisStop = routes[routeId];
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(radius: 14, child: Text('${index + 1}')),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              stop.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 40.0, top: 4.0),
                        child: Text(
                          _getStopScheduleSummary(scheduledStop),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      if (stop.notes != null && stop.notes!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 40.0, top: 4.0),
                          child: Text(
                            'Notes: ${stop.notes}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      if (routeToThisStop != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 40.0, top: 6.0),
                          child: Row(
                            children: [
                              Icon(
                                getTravelModeIcon(stop.travelMode),
                                size: 18,
                                color: theme.colorScheme.secondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Travel: ${routeToThisStop.duration} (${DistanceUtils.formatDistance(routeToThisStop.distanceInMeters, currentDistanceUnit)})',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 16),
            ),
        ],
      ),
    );
  }
}
