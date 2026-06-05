/// Human-readable distance: meters when [meters] ≤ 100, else kilometers (one decimal).
String formatDistanceForDisplay(double meters) {
  if (meters <= 100) {
    return '${meters.round()} m';
  }
  final km = meters / 1000.0;
  return '${km.toStringAsFixed(1)} km';
}

/// Distance from the user to a stop (station picker subtitles).
String formatDistanceAwayFromUser(double meters) {
  return '${formatDistanceForDisplay(meters)} away from you';
}
