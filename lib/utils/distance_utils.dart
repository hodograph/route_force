import 'package:route_force/enums/distance_unit.dart';

class DistanceUtils {
  static const double _metersPerKilometer = 1000.0;
  static const double _metersPerMile = 1609.34;

  static double metersToKilometers(int meters) {
    return meters / _metersPerKilometer;
  }

  static double metersToMiles(int meters) {
    return meters / _metersPerMile;
  }

  static String formatDistance(
    int meters,
    DistanceUnit unit, {
    int decimalPlaces = 1,
  }) {
    if (unit == DistanceUnit.kilometers) {
      final km = metersToKilometers(meters);
      return '${km.toStringAsFixed(decimalPlaces)} km';
    } else {
      final miles = metersToMiles(meters);
      return '${miles.toStringAsFixed(decimalPlaces)} miles';
    }
  }

  // Helper to get the abbreviation for the unit
  static String getUnitAbbreviation(DistanceUnit unit) {
    return unit == DistanceUnit.kilometers ? 'km' : 'mi';
  }
}
