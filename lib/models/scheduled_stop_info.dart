import 'location_stop.dart';

class ScheduledStopInfo {
  final LocationStop stop;
  final DateTime arrivalTime;
  final DateTime departureTime;
  final bool isArrivalManual;
  final bool isDepartureManual;
  final String? travelDurationToThisStopText; // from previous

  ScheduledStopInfo({
    required this.stop,
    required this.arrivalTime,
    required this.departureTime,
    required this.isArrivalManual,
    required this.isDepartureManual,
    this.travelDurationToThisStopText,
  });
}
