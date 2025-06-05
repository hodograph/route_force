import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:route_force/enums/travel_mode.dart';
import 'package:route_force/models/location_stop.dart';
import 'package:route_force/models/route_info.dart';
import 'package:route_force/models/scheduled_stop_info.dart';
import 'travel_mode_button.dart';
import 'directions_list.dart';
import 'package:route_force/enums/distance_unit.dart'; // Import DistanceUnit
import 'package:route_force/utils/distance_utils.dart'; // Import DistanceUtils

class StopDetailsContent extends StatefulWidget {
  final LocationStop stop;
  final int index;
  final List<ScheduledStopInfo> scheduleDetails;
  final Map<String, List<RouteInfo>> routes;
  final Map<String, int> selectedRouteIndices;
  final int minStopDuration;
  final int maxStopDuration;
  final int durationStep;
  final Function(String stopId, TravelMode mode) onUpdateTravelMode;
  final Function(String stopId, int duration) onUpdateStopDuration;
  final Function(String routeId, int newIndex) onUpdateRouteSelection;
  final String Function(RouteInfo routeInfo, int routeNumber)
  getTransitRouteSummaryFunction;
  final IconData Function(TravelMode mode) getTravelModeIconFunction;
  final IconData Function(String maneuver) getManeuverIconDataFunction;
  final IconData Function(String? vehicleType) getTransitVehicleIconFunction;
  final String Function(String htmlString) stripHtmlFunction;
  final LocationStop? prevStop;
  final DistanceUnit currentDistanceUnit; // Added
  final Function(String stopId, String? notes) onUpdateStopNotes;

  const StopDetailsContent({
    super.key,
    required this.stop,
    required this.index,
    required this.scheduleDetails,
    required this.routes,
    required this.selectedRouteIndices,
    required this.minStopDuration,
    required this.maxStopDuration,
    required this.durationStep,
    required this.onUpdateTravelMode,
    required this.onUpdateStopDuration,
    required this.onUpdateRouteSelection,
    required this.getTransitRouteSummaryFunction,
    required this.getTravelModeIconFunction,
    required this.getManeuverIconDataFunction,
    required this.getTransitVehicleIconFunction,
    required this.stripHtmlFunction,
    this.prevStop,
    required this.currentDistanceUnit, // Added
    required this.onUpdateStopNotes,
  });

  @override
  State<StopDetailsContent> createState() => _StopDetailsContentState();
}

class _StopDetailsContentState extends State<StopDetailsContent> {
  late TextEditingController _durationController;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(
      text: widget.stop.durationMinutes.toString(),
    );
    _notesController = TextEditingController(text: widget.stop.notes ?? '');
  }

  @override
  void didUpdateWidget(StopDetailsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stop.durationMinutes != oldWidget.stop.durationMinutes) {
      final newDurationText = widget.stop.durationMinutes.toString();
      if (_durationController.text != newDurationText) {
        _durationController.text = newDurationText;
        // Optional: Preserve cursor position if needed, though for simple numbers it's often fine
        // _durationController.selection = TextSelection.fromPosition(TextPosition(offset: _durationController.text.length));
      }
    }
    if (widget.stop.notes != oldWidget.stop.notes) {
      final newNotesText = widget.stop.notes ?? '';
      if (_notesController.text != newNotesText) {
        _notesController.text = newNotesText;
      }
    }
  }

  @override
  void dispose() {
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.index > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Travel mode from previous stop:'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children:
                      TravelMode.values.map((mode) {
                        return TravelModeButton(
                          icon: widget.getTravelModeIconFunction(mode),
                          mode: mode,
                          currentMode: widget.stop.travelMode,
                          onTap:
                              () => widget.onUpdateTravelMode(
                                widget.stop.id,
                                mode,
                              ),
                        );
                      }).toList(),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Builder(
                builder: (context) {
                  String durationLabelText =
                      'Duration: ${widget.stop.durationMinutes} minutes';
                  if (widget.index < widget.scheduleDetails.length) {
                    final scheduledInfo = widget.scheduleDetails[widget.index];
                    final effectiveDuration =
                        scheduledInfo.departureTime
                            .difference(scheduledInfo.arrivalTime)
                            .inMinutes;

                    if (widget.stop.manualDepartureTime != null ||
                        (widget.stop.manualArrivalTime != null &&
                            effectiveDuration != widget.stop.durationMinutes)) {
                      durationLabelText =
                          'Effective duration: $effectiveDuration mins.\n(Configured stop duration: ${widget.stop.durationMinutes} mins)';
                    } else {
                      durationLabelText =
                          'Stop duration: ${widget.stop.durationMinutes} minutes';
                    }
                  }
                  return Text(durationLabelText, textAlign: TextAlign.start);
                },
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Decrease by ${widget.durationStep} mins',
                    onPressed:
                        widget.stop.durationMinutes <= widget.minStopDuration
                            ? null
                            : () {
                              widget.onUpdateStopDuration(
                                widget.stop.id,
                                (widget.stop.durationMinutes -
                                        widget.durationStep)
                                    .clamp(
                                      widget.minStopDuration,
                                      widget.maxStopDuration,
                                    ),
                              );
                            },
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      // Key made stable
                      key: ValueKey('duration_tf_${widget.stop.id}'),
                      controller: _durationController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        suffixText: 'min',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 10.0,
                          horizontal: 10.0,
                        ),
                      ),
                      onFieldSubmitted: (value) {
                        final int? enteredDuration = int.tryParse(
                          _durationController.text,
                        );
                        if (enteredDuration != null) {
                          final clampedDuration = enteredDuration.clamp(
                            widget.minStopDuration,
                            widget.maxStopDuration,
                          );
                          widget.onUpdateStopDuration(
                            widget.stop.id,
                            clampedDuration,
                          );
                        } else {
                          // Invalid input, reset text field to current valid duration
                          _durationController.text =
                              widget.stop.durationMinutes.toString();
                          _durationController
                              .selection = TextSelection.fromPosition(
                            TextPosition(
                              offset: _durationController.text.length,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Increase by ${widget.durationStep} mins',
                    onPressed:
                        widget.stop.durationMinutes >= widget.maxStopDuration
                            ? null
                            : () {
                              widget.onUpdateStopDuration(
                                widget.stop.id,
                                (widget.stop.durationMinutes +
                                        widget.durationStep)
                                    .clamp(
                                      widget.minStopDuration,
                                      widget.maxStopDuration,
                                    ),
                              );
                            },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text("Quick set:", style: Theme.of(context).textTheme.bodySmall),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children:
                      [0, 15, 30, 45, 60, 90, 120, 180].map((int mins) {
                        bool isSelected = widget.stop.durationMinutes == mins;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: ActionChip(
                            avatar:
                                isSelected
                                    ? Icon(
                                      Icons.check,
                                      size: 16,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onPrimary,
                                    )
                                    : null,
                            label: Text('$mins min'),
                            backgroundColor:
                                isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                            labelStyle: TextStyle(
                              color:
                                  isSelected
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : null,
                            ),
                            onPressed:
                                () => widget.onUpdateStopDuration(
                                  widget.stop.id,
                                  mins,
                                ),
                          ),
                        );
                      }).toList(),
                ),
              ),
              // Add AI Suggestion display
              if (widget.stop.aiSuggestedDurationMinutes != null &&
                  widget.stop.aiSuggestedDurationMinutes! > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 16,
                        color: Colors.orangeAccent.shade200,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'AI Suggestion: ${widget.stop.aiSuggestedDurationMinutes} min',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      if (widget.stop.durationMinutes == 0 ||
                          widget.stop.durationMinutes !=
                              widget.stop.aiSuggestedDurationMinutes!)
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'Use',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () {
                            widget.onUpdateStopDuration(
                              widget.stop.id,
                              widget.stop.aiSuggestedDurationMinutes!,
                            );
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Section for Opening Hours (conditionally displayed for the arrival day)
        Builder(
          builder: (context) {
            if (widget.index < widget.scheduleDetails.length) {
              final ScheduledStopInfo currentScheduledStop =
                  widget.scheduleDetails[widget.index];
              final Locale currentLocale = Localizations.localeOf(context);
              final String arrivalDayName = DateFormat(
                'EEEE',
                currentLocale.toString(),
              ).format(currentScheduledStop.arrivalTime);
              final String arrivalDateFormatted = DateFormat(
                'MMM d, yyyy',
                currentLocale.toString(),
              ).format(currentScheduledStop.arrivalTime);

              String displayMessage;
              final String titleText =
                  'Business Hours (on $arrivalDateFormatted - $arrivalDayName):';

              if (widget.stop.openingHoursWeekdayText != null &&
                  widget.stop.openingHoursWeekdayText!.isNotEmpty) {
                String? foundHours;
                for (final String dayHourText
                    in widget.stop.openingHoursWeekdayText!) {
                  if (dayHourText.toLowerCase().startsWith(
                    arrivalDayName.toLowerCase(),
                  )) {
                    foundHours =
                        dayHourText; // Display the full "DayName: Hours" string
                    break;
                  }
                }
                displayMessage =
                    foundHours ??
                    'Hours for $arrivalDayName not available at this location.';
              } else {
                displayMessage =
                    'No opening hours information provided for this stop.';
              }

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayMessage,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink(); // If index is out of bounds for scheduleDetails
          },
        ), // This closes the Business Hours Builder. The next widget should be the Route Options.
        // Notes Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notes for this stop:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8.0),
              TextFormField(
                // Key made stable to prevent focus loss on every character typed
                key: ValueKey('notes_tf_${widget.stop.id}'),
                controller: _notesController,
                decoration: const InputDecoration(
                  hintText:
                      'Add any notes here (e.g., gate code, contact person)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                onChanged: (value) {
                  // Debounce or save on lost focus might be better for performance
                  // For simplicity, saving on every change. This ensures that when
                  // focus is lost (e.g., by tapping outside), the latest notes are saved.
                  // Consider using a FocusNode and onFocusChange to save when focus is lost.
                  widget.onUpdateStopNotes(widget.stop.id, value);
                },
                onFieldSubmitted: (value) {
                  widget.onUpdateStopNotes(
                    widget.stop.id,
                    _notesController.text.trim().isEmpty
                        ? null
                        : _notesController.text.trim(),
                  );
                },
                onTapOutside: (event) {
                  // With `onChanged` active, notes are saved as they are typed.
                  // Tapping outside will simply unfocus the field.
                  FocusManager.instance.primaryFocus?.unfocus();
                },
              ),
            ],
          ),
        ),
        if (widget.index >
            0) // This is the start of the "Route Options" section
          Builder(
            builder: (context) {
              // This builder is for "Route Options"
              if (widget.prevStop == null) {
                return const SizedBox.shrink(); // Should not happen if index > 0
              }
              final routeId = '${widget.prevStop!.id}-${widget.stop.id}';
              final List<RouteInfo>? currentRouteOptions =
                  widget.routes[routeId];
              final int currentSelectedRouteIndex =
                  widget.selectedRouteIndices[routeId] ?? 0;

              if (currentRouteOptions != null &&
                  currentRouteOptions.length > 1) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route Options (${currentRouteOptions.length} available):',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      DropdownButton<int>(
                        isExpanded: true,
                        value: currentSelectedRouteIndex,
                        hint: const Text("Select a route"),
                        items: List.generate(currentRouteOptions.length, (i) {
                          final routeOpt = currentRouteOptions[i];
                          String summaryDisplay;
                          if (widget.stop.travelMode == TravelMode.transit) {
                            List<String> lineNames = [];
                            for (var stepInfo in routeOpt.steps) {
                              if (stepInfo is Map<String, dynamic> &&
                                  stepInfo['travel_mode'] == 'TRANSIT') {
                                final transitDetails =
                                    stepInfo['transit_details']
                                        as Map<String, dynamic>?;
                                final line =
                                    transitDetails?['line']
                                        as Map<String, dynamic>?;
                                if (line != null) {
                                  String? shortName =
                                      line['short_name'] as String?;
                                  String? longName = line['name'] as String?;
                                  String nameToAdd =
                                      shortName ?? longName ?? "";
                                  if (nameToAdd.isNotEmpty &&
                                      !lineNames.contains(nameToAdd)) {
                                    lineNames.add(nameToAdd);
                                  }
                                }
                              }
                            }
                            if (lineNames.isNotEmpty) {
                              summaryDisplay = "via ${lineNames.join(', ')}";
                            } else {
                              summaryDisplay = widget
                                  .getTransitRouteSummaryFunction(
                                    routeOpt,
                                    i + 1,
                                  );
                            }
                          } else {
                            summaryDisplay =
                                routeOpt.summary ?? 'Route ${i + 1}';
                            if (summaryDisplay.isEmpty ||
                                (routeOpt.summary != null &&
                                    routeOpt.summary!.toLowerCase().startsWith(
                                      "route ",
                                    ))) {
                              summaryDisplay = 'Route ${i + 1}';
                            }
                          }

                          Widget itemChild;
                          String? transitIconUrl;

                          if (widget.stop.travelMode == TravelMode.transit) {
                            for (var stepInfo in routeOpt.steps) {
                              if (stepInfo is Map<String, dynamic> &&
                                  stepInfo['travel_mode'] == 'TRANSIT') {
                                final transitStepDetails =
                                    stepInfo['transit_details']
                                        as Map<String, dynamic>?;
                                final lineDetails =
                                    transitStepDetails?['line']
                                        as Map<String, dynamic>?;
                                final vehicleDetails =
                                    lineDetails?['vehicle']
                                        as Map<String, dynamic>?;

                                String? potentialIconUrl =
                                    vehicleDetails?['icon'] as String? ??
                                    lineDetails?['icon'] as String?;

                                if (potentialIconUrl != null &&
                                    potentialIconUrl.startsWith('https://')) {
                                  transitIconUrl = potentialIconUrl;
                                  break;
                                }
                              }
                            }
                          }

                          if (transitIconUrl != null) {
                            itemChild = Row(
                              children: [
                                Image.network(
                                  transitIconUrl,
                                  height:
                                      24, // Adjusted size for better visibility
                                  width: 24,
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          const SizedBox(
                                            width: 24,
                                          ), // Keep space consistent
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$summaryDisplay (${routeOpt.duration}, ${DistanceUtils.formatDistance(routeOpt.distanceInMeters, widget.currentDistanceUnit)})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          } else {
                            // Use currentDistanceUnit here
                            itemChild = Text(
                              '$summaryDisplay (${routeOpt.duration}, ${DistanceUtils.formatDistance(routeOpt.distanceInMeters, widget.currentDistanceUnit)})',
                            );
                          }
                          return DropdownMenuItem<int>(
                            value: i,
                            child: itemChild,
                          );
                        }),
                        onChanged: (int? newIndex) {
                          if (newIndex != null) {
                            widget.onUpdateRouteSelection(routeId, newIndex);
                          }
                        },
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        if (widget.index > 0)
          Builder(
            builder: (context) {
              if (widget.prevStop == null) {
                return const SizedBox.shrink(); // Should not happen if index > 0
              }
              final routeIdFromPrevious =
                  '${widget.prevStop!.id}-${widget.stop.id}';
              final List<RouteInfo>? routeOptions =
                  widget.routes[routeIdFromPrevious];
              final int selectedIdx =
                  widget.selectedRouteIndices[routeIdFromPrevious] ?? 0;

              if (routeOptions != null &&
                  routeOptions.isNotEmpty &&
                  selectedIdx < routeOptions.length) {
                final selectedRouteDetails = routeOptions[selectedIdx];
                if (selectedRouteDetails.steps.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: DirectionsList(
                      steps: selectedRouteDetails.steps,
                      getManeuverIconData: widget.getManeuverIconDataFunction,
                      getTransitVehicleIcon:
                          widget.getTransitVehicleIconFunction,
                      currentDistanceUnit:
                          widget.currentDistanceUnit, // Pass down
                      stripHtmlIfNeeded: widget.stripHtmlFunction,
                      primaryColor: Theme.of(context).highlightColor,
                    ),
                  );
                }
              }
              return const SizedBox.shrink();
            },
          ),
      ],
    );
  }
}
