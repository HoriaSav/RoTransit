/// Identifies a downloadable offline timetable bundle shown in Settings.
enum TimetableDownloadSourceId {
  gtfsOfflinePack,
}

class TimetableDownloadSource {
  const TimetableDownloadSource({required this.id});

  final TimetableDownloadSourceId id;
}

/// Offline timetable sources the app exposes in Settings (extensible later).
const kTimetableDownloadSources = <TimetableDownloadSource>[
  TimetableDownloadSource(id: TimetableDownloadSourceId.gtfsOfflinePack),
];
