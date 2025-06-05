import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:route_force/enums/stop_action.dart';
import 'package:route_force/enums/travel_mode.dart';
import 'package:route_force/models/location_stop.dart';
import 'package:route_force/models/route_info.dart';
import 'package:route_force/models/scheduled_stop_info.dart';
import 'stop_list_item.dart';
import 'package:route_force/enums/distance_unit.dart'; // Import DistanceUnit

class TripSheetContent extends StatelessWidget {
  final ScrollController? scrollController; // Made nullable
  final DateTime tripStartTime;
  final Function(DateTime) onTripStartTimeChanged;
  final TextEditingController searchController;
  final List<dynamic> placePredictions;
  final Function(String placeId) onPlaceSelected;
  final bool isPickingNewStopOnMap;
  final VoidCallback onTogglePickNewStopOnMap;
  final List<LocationStop> stops;
  final Map<String, ExpansionTileController> tileControllers;
  final String? expandedStopId;
  final Function(String stopId, bool expanded) onExpansionChanged;
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
  final Function(String stopId, TravelMode mode) updateTravelMode;
  final Function(String stopId, int duration) updateStopDuration;
  final List<ScheduledStopInfo> Function() computeScheduleDetails;
  final Function(String routeId, int newIndex) updatePolylinesForSegment;
  final Widget Function(List<dynamic> steps) buildStepList;
  final Function(int oldIndex, int newIndex) onReorder;

  final String Function(RouteInfo routeInfo, int routeNumber)
  getTransitRouteSummaryFunction;
  final IconData Function(String maneuver) getManeuverIconDataFunction;
  final IconData Function(String? vehicleType) getTransitVehicleIconFunction;
  final String Function(String htmlString) stripHtmlFunction;
  final int minStopDuration;
  final int maxStopDuration;
  final int durationStep;
  final bool isSheetMode;
  final String Function(int stopIndex)
  getStopOpeningHoursWarningFunction; // Added
  final Future<void> Function()? onSaveTrip; // Added for saving trip
  // --- Added for Saved Trips ---
  final List<Map<String, dynamic>> savedTrips;
  final bool isLoadingSavedTrips;
  final Function(Map<String, dynamic> tripData, String tripDocId) onLoadTrip;

  // --- Added for Participants ---
  final List<Map<String, String>>
  participantUserDetails; // e.g., {'id': 'uid', 'displayName': 'User Name', 'email': 'user@example.com'}
  final VoidCallback onAddParticipant;
  final Function(String userId) onRemoveParticipant;
  final bool isLoadingParticipants;
  final Function(String tripDocId) onDeleteTrip;
  final String? tripOwnerId; // Added to identify the actual trip owner

  final DistanceUnit currentDistanceUnit; // Added
  final Function(String stopId, String? notes) onUpdateStopNotes; // Added
  const TripSheetContent({
    super.key,
    this.scrollController, // Made nullable
    required this.tripStartTime,
    required this.onTripStartTimeChanged,
    required this.searchController,
    required this.placePredictions,
    required this.onPlaceSelected,
    required this.isPickingNewStopOnMap,
    required this.onTogglePickNewStopOnMap,
    required this.stops,
    required this.tileControllers,
    required this.expandedStopId,
    required this.onExpansionChanged,
    required this.getStopScheduleSummary,
    required this.getTravelModeIcon,
    required this.routes,
    required this.selectedRouteIndices,
    required this.onStopActionSelected,
    required this.updateTravelMode,
    required this.updateStopDuration,
    required this.computeScheduleDetails,
    required this.updatePolylinesForSegment,
    required this.buildStepList,
    required this.onReorder,
    required this.getTransitRouteSummaryFunction,
    required this.getManeuverIconDataFunction,
    required this.getTransitVehicleIconFunction,
    required this.stripHtmlFunction,
    required this.minStopDuration,
    required this.maxStopDuration,
    required this.durationStep,
    this.isSheetMode = true, // Default to true for existing behavior
    required this.getStopOpeningHoursWarningFunction, // Added
    this.onSaveTrip, // Added
    // --- Added for Saved Trips ---
    required this.savedTrips,
    required this.isLoadingSavedTrips,
    required this.onLoadTrip,
    required this.onDeleteTrip,
    // --- Added for Participants ---
    required this.participantUserDetails,
    required this.onAddParticipant,
    required this.onRemoveParticipant,
    required this.isLoadingParticipants,
    required this.onUpdateStopNotes, // Added
    required this.tripOwnerId, // Added
    required this.currentDistanceUnit, // Added
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height:
          isSheetMode ? null : double.infinity, // Fill height in desktop mode
      decoration:
          isSheetMode
              ? BoxDecoration(
                color: Theme.of(context).cardColor, // Use theme's card color
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.5),
                    spreadRadius: 2, // Adjusted for potentially darker themes
                    blurRadius: 7,
                    offset: const Offset(0, 3),
                  ),
                ],
              )
              : null, // No special decoration when not in sheet mode (e.g. inside a Card)
      child: SingleChildScrollView(
        controller: scrollController,
        child: Column(
          children: [
            if (isSheetMode) ...[
              const SizedBox(height: 10),
              Container(
                height: 5,
                width: 50,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Plan Your Trip',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Start Time'),
                    subtitle: Text(
                      DateFormat('MMM dd, yyyy - h:mm a').format(tripStartTime),
                    ),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: tripStartTime,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2101),
                      );
                      if (pickedDate != null && context.mounted) {
                        final TimeOfDay? pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(tripStartTime),
                        );
                        if (pickedTime != null) {
                          onTripStartTimeChanged(
                            DateTime(
                              pickedDate.year,
                              pickedDate.month,
                              pickedDate.day,
                              pickedTime.hour,
                              pickedTime.minute,
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    autofocus: false,
                    onTapOutside: (event) {
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search for a place',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (placePredictions.isNotEmpty)
                    SizedBox(
                      // Use SizedBox for fixed height container
                      height: 200,
                      child: ListView.builder(
                        itemCount: placePredictions.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(placePredictions[index]['description']),
                            onTap:
                                () => onPlaceSelected(
                                  placePredictions[index]['place_id'],
                                ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  Center(
                    child: ElevatedButton.icon(
                      icon: Icon(
                        isPickingNewStopOnMap
                            ? Icons.cancel
                            : Icons.add_location_alt_outlined,
                      ),
                      label: Text(
                        isPickingNewStopOnMap
                            ? 'Cancel Picking on Map'
                            : 'Pick New Stop on Map',
                      ),
                      onPressed: onTogglePickNewStopOnMap,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (onSaveTrip != null) ...[
                    Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save_alt_outlined),
                        label: const Text('Save Trip to Cloud'),
                        onPressed: onSaveTrip,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // --- Section for Participants ---
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Participants',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        tooltip: 'Add Participant',
                        onPressed: onAddParticipant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isLoadingParticipants)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (participantUserDetails.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Center(
                        child: Text(
                          'No other participants. Click the button above to add.',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children:
                          participantUserDetails.map((user) {
                            bool isOwner = user['id'] == tripOwnerId;
                            return Chip(
                              avatar: CircleAvatar(
                                backgroundColor:
                                    isOwner
                                        ? Theme.of(
                                          context,
                                        ).primaryColor.withAlpha(100)
                                        : null,
                                child: Text(
                                  user['displayName']![0].toUpperCase(),
                                  style: TextStyle(
                                    color:
                                        isOwner
                                            ? Theme.of(context).primaryColorDark
                                            : null,
                                  ),
                                ),
                              ),
                              label: Text(
                                user['displayName']! +
                                    (isOwner ? " (Owner)" : ""),
                              ),
                              onDeleted:
                                  !isOwner
                                      ? () => onRemoveParticipant(user['id']!)
                                      : null,
                              deleteIcon:
                                  !isOwner
                                      ? Icon(
                                        Icons.cancel,
                                        size: 18,
                                        color: Colors.red.shade700,
                                      )
                                      : null,
                            );
                          }).toList(),
                    ),
                  const SizedBox(height: 16),
                  const Divider(),

                  const Text(
                    'Your Stops',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (stops.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          'Search and add locations to plan your trip',
                        ),
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: stops.length,
                      itemBuilder: (context, index) {
                        final stop = stops[index];
                        final tileController = tileControllers.putIfAbsent(
                          stop.id,
                          () => ExpansionTileController(),
                        );
                        return StopListItem(
                          key: ValueKey(stop.id), // Ensure key is passed
                          stop: stop,
                          index: index,
                          tileController: tileController,
                          isExpanded: expandedStopId == stop.id,
                          onExpansionChanged:
                              (expanded) =>
                                  onExpansionChanged(stop.id, expanded),
                          getStopScheduleSummary: getStopScheduleSummary,
                          getTravelModeIcon: getTravelModeIcon,
                          routes: routes,
                          selectedRouteIndices: selectedRouteIndices,
                          onStopActionSelected: onStopActionSelected,
                          onUpdateTravelMode: updateTravelMode,
                          onUpdateStopDuration: updateStopDuration,
                          computeScheduleDetails: computeScheduleDetails,
                          onUpdatePolylinesForSegment:
                              updatePolylinesForSegment,
                          getTransitRouteSummaryFunction:
                              getTransitRouteSummaryFunction,
                          getManeuverIconDataFunction:
                              getManeuverIconDataFunction,
                          getTransitVehicleIconFunction:
                              getTransitVehicleIconFunction,
                          stripHtmlFunction: stripHtmlFunction,
                          minStopDuration: minStopDuration,
                          maxStopDuration: maxStopDuration,
                          durationStep: durationStep,
                          allStops: stops,
                          getStopOpeningHoursWarning:
                              getStopOpeningHoursWarningFunction, // Pass down
                          currentDistanceUnit: currentDistanceUnit, // Pass down
                          onUpdateStopNotes: onUpdateStopNotes, // Pass down
                        );
                      },
                      onReorder: onReorder,
                    ),
                  // --- Section for Saved Trips ---
                  if (stops.isEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Or Load a Saved Trip',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isLoadingSavedTrips)
                      const Center(child: CircularProgressIndicator())
                    else if (savedTrips.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: Text('No saved trips found.')),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: savedTrips.length,
                        itemBuilder: (context, index) {
                          final trip = savedTrips[index];
                          final tripData = trip['data'] as Map<String, dynamic>;
                          final tripDocId = trip['id'] as String;
                          final tripName =
                              tripData['tripName'] as String? ?? 'Unnamed Trip';
                          final tripStartTime =
                              (tripData['tripStartTime'] as Timestamp).toDate();

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              title: Text(tripName),
                              subtitle: Text(
                                'Starts: ${DateFormat('MMM dd, yyyy - h:mm a').format(tripStartTime)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.download_for_offline,
                                      color: Colors.blue,
                                    ),
                                    tooltip: 'Load Trip',
                                    onPressed:
                                        () => onLoadTrip(tripData, tripDocId),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Colors.red.shade700,
                                    ),
                                    tooltip: 'Delete Trip',
                                    onPressed: () => onDeleteTrip(tripDocId),
                                  ),
                                ],
                              ),
                              onTap: () => onLoadTrip(tripData, tripDocId),
                            ),
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
