// Enum for stop options menu
enum StopAction {
  editManualArrival,
  clearManualArrival,
  editManualDeparture,
  clearManualDeparture,
  editDepartureLocation, // Triggers text search UI
  pickDepartureOnMap, // Triggers map picking mode
  resetDepartureToArrival,
  removeStop,
}
