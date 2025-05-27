import 'package:flutter/material.dart';
import 'package:route_force/enums/stop_action.dart';
import 'package:route_force/enums/travel_mode.dart';
import 'package:route_force/models/location_stop.dart';
import 'package:route_force/models/route_info.dart';
import 'package:route_force/models/scheduled_stop_info.dart';
import 'stop_details_content.dart';

class StopListItem extends StatelessWidget {
  final LocationStop stop;
  final int index;
  final ExpansionTileController tileController;
  final bool isExpanded;
  final Function(bool expanded) onExpansionChanged;
  final String Function(int stopIndex) getStopScheduleSummary;
  final IconData Function(TravelMode mode) getTravelModeIcon;
  final Map<String, List<RouteInfo>> routes;
  final Map<String, int> selectedRouteIndices;
  final Function(
    StopAction action,
    String stopId,
    int index,
    BuildContext itemContext,
  )
  onStopActionSelected;
  final Function(String stopId, TravelMode mode) onUpdateTravelMode;
  final Function(String stopId, int duration) onUpdateStopDuration;
  final List<ScheduledStopInfo> Function() computeScheduleDetails;
  final Function(String routeId, int newIndex) onUpdatePolylinesForSegment;

  final String Function(RouteInfo routeInfo, int routeNumber)
  getTransitRouteSummaryFunction;
  final IconData Function(String maneuver) getManeuverIconDataFunction;
  final IconData Function(String? vehicleType) getTransitVehicleIconFunction;
  final String Function(String htmlString) stripHtmlFunction;
  final int minStopDuration;
  final int maxStopDuration;
  final int durationStep;
  final List<LocationStop> allStops; // Needed for prevStop access in subtitle
  final String Function(int stopIndex) getStopOpeningHoursWarning;
  final Function(String stopId, String? notes) onUpdateStopNotes;

  const StopListItem({
    super.key,
    required this.stop,
    required this.index,
    required this.tileController,
    required this.isExpanded,
    required this.onExpansionChanged,
    required this.getStopScheduleSummary,
    required this.getTravelModeIcon,
    required this.routes,
    required this.selectedRouteIndices,
    required this.onStopActionSelected,
    required this.onUpdateTravelMode,
    required this.onUpdateStopDuration,
    required this.computeScheduleDetails,
    required this.onUpdatePolylinesForSegment,
    required this.getTransitRouteSummaryFunction,
    required this.getManeuverIconDataFunction,
    required this.getTransitVehicleIconFunction,
    required this.stripHtmlFunction,
    required this.minStopDuration,
    required this.maxStopDuration,
    required this.durationStep,
    required this.allStops,
    required this.getStopOpeningHoursWarning,
    required this.onUpdateStopNotes,
  });

  @override
  Widget build(BuildContext context) {
    final String warningText = getStopOpeningHoursWarning(index);
    return Card(
      key: ValueKey(stop.id),
      child: ExpansionTile(
        controller: tileController,
        initiallyExpanded: isExpanded,
        onExpansionChanged: onExpansionChanged,
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(stop.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(getStopScheduleSummary(index)),
            if (warningText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade700,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        warningText,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (stop.departurePosition != null &&
                stop.departurePosition != stop.position)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  'Departs from: ${stop.effectiveDepartureName}',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            if (index > 0)
              Builder(
                builder: (context) {
                  final prevStop = allStops[index - 1];
                  final routeIdFromPrevious = '${prevStop.id}-${stop.id}';
                  String durationText = '(No route)';
                  final List<RouteInfo>? routeOptions =
                      routes[routeIdFromPrevious];
                  final int selectedIdx =
                      selectedRouteIndices[routeIdFromPrevious] ?? 0;

                  if (routeOptions != null &&
                      routeOptions.isNotEmpty &&
                      selectedIdx < routeOptions.length) {
                    durationText = '(${routeOptions[selectedIdx].duration})';
                  }

                  return Row(
                    children: [
                      Icon(
                        getTravelModeIcon(stop.travelMode),
                        size: 16,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        durationText,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
        trailing: PopupMenuButton<StopAction>(
          icon: const Icon(Icons.more_vert),
          tooltip: "More options",
          onSelected:
              (action) => onStopActionSelected(action, stop.id, index, context),
          itemBuilder: (BuildContext context) {
            List<PopupMenuEntry<StopAction>> items = [];
            items.add(
              const PopupMenuItem<StopAction>(
                value: StopAction.editManualArrival,
                child: Text('Set/Edit Manual Arrival Time'),
              ),
            );
            if (stop.manualArrivalTime != null) {
              items.add(
                const PopupMenuItem<StopAction>(
                  value: StopAction.clearManualArrival,
                  child: Text('Clear Manual Arrival Time'),
                ),
              );
            }
            items.add(
              const PopupMenuItem<StopAction>(
                value: StopAction.editManualDeparture,
                child: Text('Set/Edit Manual Departure Time'),
              ),
            );
            if (stop.manualDepartureTime != null) {
              items.add(
                const PopupMenuItem<StopAction>(
                  value: StopAction.clearManualDeparture,
                  child: Text('Clear Manual Departure Time'),
                ),
              );
            }
            items.add(const PopupMenuDivider());
            items.add(
              const PopupMenuItem<StopAction>(
                value: StopAction.editDepartureLocation,
                child: Text('Set Departure (Search)'),
              ),
            );
            items.add(
              const PopupMenuItem<StopAction>(
                value: StopAction.pickDepartureOnMap,
                child: Text('Set Departure (Map Pick)'),
              ),
            );
            if (stop.departurePosition != null &&
                stop.departurePosition != stop.position) {
              items.add(
                const PopupMenuItem<StopAction>(
                  value: StopAction.resetDepartureToArrival,
                  child: Text('Use Arrival for Departure'),
                ),
              );
            }
            items.add(const PopupMenuDivider());
            items.add(
              PopupMenuItem<StopAction>(
                value: StopAction.removeStop,
                child: Text(
                  'Remove Stop',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            );
            return items;
          },
        ),
        children: [
          StopDetailsContent(
            stop: stop,
            index: index,
            scheduleDetails: computeScheduleDetails(),
            routes: routes,
            selectedRouteIndices: selectedRouteIndices,
            minStopDuration: minStopDuration,
            maxStopDuration: maxStopDuration,
            durationStep: durationStep,
            onUpdateTravelMode: onUpdateTravelMode,
            onUpdateStopDuration: onUpdateStopDuration,
            onUpdateRouteSelection: onUpdatePolylinesForSegment,
            getTransitRouteSummaryFunction: getTransitRouteSummaryFunction,
            getTravelModeIconFunction: getTravelModeIcon,
            getManeuverIconDataFunction: getManeuverIconDataFunction,
            getTransitVehicleIconFunction: getTransitVehicleIconFunction,
            stripHtmlFunction: stripHtmlFunction,
            prevStop: index > 0 ? allStops[index - 1] : null,
            onUpdateStopNotes: onUpdateStopNotes,
          ),
        ],
      ),
    );
  }
}
