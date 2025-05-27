import 'package:flutter/material.dart';
import 'package:route_force/enums/travel_mode.dart' as travel_mode_enum;

class MapDisplayHelpers {
  static IconData getTravelModeIcon(travel_mode_enum.TravelMode mode) {
    switch (mode) {
      case travel_mode_enum.TravelMode.driving:
        return Icons.directions_car;
      case travel_mode_enum.TravelMode.walking:
        return Icons.directions_walk;
      case travel_mode_enum.TravelMode.bicycling:
        return Icons.directions_bike;
      case travel_mode_enum.TravelMode.transit:
        return Icons.directions_transit;
    }
  }

  static IconData getManeuverIconData(String maneuver) {
    switch (maneuver.toLowerCase()) {
      case 'turn-sharp-left':
        return Icons.turn_sharp_left;
      case 'turn-sharp-right':
        return Icons.turn_sharp_right;
      case 'uturn-left':
      case 'uturn': // Generic u-turn if 'uturn-left' or 'uturn-right' not specified
        return Icons.u_turn_left;
      case 'uturn-right':
        return Icons.u_turn_right;
      case 'turn-slight-left':
        return Icons.turn_slight_left;
      case 'turn-slight-right':
        return Icons.turn_slight_right;
      case 'turn-left':
        return Icons.turn_left;
      case 'turn-right':
        return Icons.turn_right;
      case 'straight':
        return Icons.straight;
      case 'ramp-left':
        return Icons.ramp_left;
      case 'ramp-right':
        return Icons.ramp_right;
      case 'merge':
        return Icons.merge_type;
      case 'fork-left':
        return Icons.fork_left;
      case 'fork-right':
        return Icons.fork_right;
      case 'roundabout-left':
        return Icons.roundabout_left;
      case 'roundabout-right':
        return Icons.roundabout_right;
      case 'keep-left':
        return Icons
            .subdirectory_arrow_left; // Or a more specific keep_left if available
      case 'keep-right':
        return Icons
            .subdirectory_arrow_right; // Or a more specific keep_right if available
      case 'ferry':
        return Icons.directions_ferry;
      case 'ferry-train': // If your API distinguishes this
        return Icons
            .train; // Or combine ferry and train icon if desired/possible
      case 'destination':
        return Icons.flag;
      case 'destination-left':
      case 'destination-right':
        return Icons.flag_circle; // Example, adjust as needed
      default:
        return Icons.directions; // Default for unknown maneuvers
    }
  }

  static IconData getTransitVehicleIcon(String? vehicleType) {
    switch (vehicleType?.toUpperCase()) {
      case 'BUS':
        return Icons.directions_bus;
      case 'SUBWAY':
      case 'METRO_RAIL':
      case 'MONORAIL':
      case 'HEAVY_RAIL':
      case 'COMMUTER_TRAIN':
        return Icons.directions_subway;
      case 'TRAIN':
        return Icons.train;
      case 'TRAM':
      case 'LIGHT_RAIL':
        return Icons.tram;
      case 'FERRY':
        return Icons.directions_ferry;
      case 'CABLE_CAR':
        return Icons.cabin; // Placeholder, consider a more specific icon
      case 'GONDOLA_LIFT':
        return Icons.airline_seat_recline_normal; // Placeholder
      case 'FUNICULAR':
        return Icons.stairs; // Placeholder
      case 'TAXI':
        return Icons.local_taxi;
      default:
        return Icons.directions_transit_filled;
    }
  }

  static String stripHtmlIfNeeded(String htmlString) {
    return htmlString
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
