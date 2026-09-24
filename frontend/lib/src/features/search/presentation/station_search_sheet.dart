part of 'search_tab.dart';

class _StationSearchSheet extends ConsumerStatefulWidget {
  const _StationSearchSheet({
    required this.title,
    required this.cityId,
    required this.initialQuery,
  });

  final String title;
  final String? cityId;
  final String initialQuery;

  @override
  ConsumerState<_StationSearchSheet> createState() =>
      _StationSearchSheetState();
}

class _StationSearchSheetState extends ConsumerState<_StationSearchSheet> {
  static const int _nearbyRadiusM = 5000;
  static const int _nearbyListLimit = 40;

  late final TextEditingController _queryCtrl;
  Timer? _debounce;
  bool _loading = false;
  List<StopSearchItem> _results = const [];
  int _loadGen = 0;
  bool _pickingGps = false;

  UserLocationState get _userLoc => ref.read(userLocationProvider);

  double get _refLat => _userLoc.lat ?? kDefaultSearchRefLat;
  double get _refLon => _userLoc.lon ?? kDefaultSearchRefLon;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery);
    _queryCtrl.addListener(_onQueryChanged);
    _bootstrapSheet();
  }

  Future<void> _bootstrapSheet() async {
    if (!mounted || widget.cityId == null) return;
    final gen = ++_loadGen;
    setState(() => _loading = true);

    final loc = await ref.read(userLocationProvider.notifier).resolve();
    if (!mounted || gen != _loadGen) return;

    await _loadNearbyForRef(
      loc.hasFix ? loc.lat! : kDefaultSearchRefLat,
      loc.hasFix ? loc.lon! : kDefaultSearchRefLon,
      gen: gen,
      showGlobalSpinner: true,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.removeListener(_onQueryChanged);
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNearbyForRef(
    double lat,
    double lon, {
    required int gen,
    required bool showGlobalSpinner,
  }) async {
    if (!mounted || widget.cityId == null) return;
    if (gen != _loadGen) return;

    if (showGlobalSpinner) {
      setState(() => _loading = true);
    }

    final cityId = widget.cityId!;
    final offline = ref.read(offlineTransitCacheRepositoryProvider);
    final packMeta = await offline.getMetaForCity(cityId);
    var fromPack = const <StopSearchItem>[];
    if (packMeta != null) {
      fromPack = await offline.nearbyStopsFromPack(
        cityId: cityId,
        lat: lat,
        lon: lon,
        radiusMeters: _nearbyRadiusM,
        limit: _nearbyListLimit,
      );
    }

    if (!mounted || gen != _loadGen) return;
    if (fromPack.isNotEmpty) {
      setState(() {
        _results = fromPack;
        _loading = false;
      });
    }

    final skipNetwork = !await isDeviceOnline();
    if (skipNetwork) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        if (fromPack.isEmpty) _results = const [];
        _loading = false;
      });
      return;
    }

    try {
      final stops = await ref.read(routeApiRepositoryProvider).getNearbyStops(
            cityId: cityId,
            lat: lat,
            lon: lon,
            radiusMeters: _nearbyRadiusM,
          );
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _results = stops
            .map(
              (e) => StopSearchItem(
                stopId: e.stopId,
                name: e.name,
                lat: e.lat,
                lon: e.lon,
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        if (_results.isEmpty) _results = const [];
        _loading = false;
      });
    }
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _searchStops);
  }

  Future<void> _searchStops() async {
    if (widget.cityId == null) return;
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) {
      final gen = ++_loadGen;
      await _loadNearbyForRef(
        _refLat,
        _refLon,
        gen: gen,
        showGlobalSpinner: true,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final offlineRepo = ref.read(offlineTransitCacheRepositoryProvider);
      final offlineItems = await offlineRepo.searchStopsInPack(
        cityId: widget.cityId!,
        query: q,
        limit: 20,
        refLat: _refLat,
        refLon: _refLon,
      );

      // Show local results immediately (including one-letter and diacritics-folded matches).
      if (!mounted) return;
      if (offlineItems.isNotEmpty) {
        setState(() => _results = offlineItems);
      }

      final onlineAllowed = await isDeviceOnline();
      if (onlineAllowed) {
        final remoteItems = await ref.read(routeApiRepositoryProvider).searchStops(
          cityId: widget.cityId!,
          query: q,
          limit: 20,
          refLat: _refLat,
          refLon: _refLon,
        );
        if (!mounted) return;
        // Keep local fallback stable, then append backend-only suggestions.
        final merged = <StopSearchItem>[];
        final seen = <String>{};
        for (final item in offlineItems) {
          final key = '${item.stopId}|${item.name}|${item.lat}|${item.lon}';
          if (seen.add(key)) merged.add(item);
        }
        for (final item in remoteItems) {
          final key = '${item.stopId}|${item.name}|${item.lat}|${item.lon}';
          if (seen.add(key)) merged.add(item);
        }
        setState(() {
          if (merged.isNotEmpty) {
            _results = merged.take(20).toList();
          } else {
            _results = const [];
          }
        });
      } else if (offlineItems.isEmpty) {
        setState(() => _results = const []);
      }
    } catch (_) {
      if (!mounted) return;
      // Keep any already-shown fallback results instead of clearing them on network/backend errors.
      setState(() {
        if (_results.isEmpty) _results = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCurrentLocation() async {
    if (_pickingGps) return;
    setState(() => _pickingGps = true);
    final l10n = AppLocalizations.of(context);
    try {
      var loc = ref.read(userLocationProvider);
      if (!loc.hasFix) {
        loc = await ref.read(userLocationProvider.notifier).resolve();
      }
      if (!mounted) return;
      if (!loc.hasFix ||
          loc.lat == null ||
          loc.lon == null ||
          !isUsableLatLon(loc.lat!, loc.lon!)) {
        final failure = await localizedUserLocationFailure(l10n);
        if (!mounted) return;
        showUserMessage(
          context,
          AppUserMessage.custom(
            failure.message,
            severity: UserMessageSeverity.warning,
            actionLabel: failure.showSettingsAction ? l10n.openSettings : null,
          ),
          onAction: failure.showSettingsAction ? openUserLocationSettings : null,
        );
        return;
      }
      final lat = loc.lat!;
      final lon = loc.lon!;
      final nav = Navigator.of(context);
      if (!nav.canPop()) return;
      nav.pop(
        _StationSelectionResult(
          station: StopSearchItem(
            stopId: coordinateStopId(kind: 'gps', lat: lat, lon: lon),
            name: l10n.searchCurrentLocation,
            lat: lat,
            lon: lon,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final userLoc = ref.watch(userLocationProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(
              const _StationSelectionResult(pickOnMap: true),
            ),
            icon: const Icon(Icons.map_outlined),
            label: Text(l10n.searchSelectOnMap),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            children: [
              TextField(
                controller: _queryCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.searchStationHint,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        itemCount:
                            1 + _results.length + (_results.isEmpty ? 1 : 0),
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final locating =
                                _pickingGps || userLoc.isResolving;
                            return ListTile(
                              leading: locating
                                  ? SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.onSurface,
                                      ),
                                    )
                                  : Icon(
                                      Icons.my_location,
                                      color: scheme.onSurface,
                                    ),
                              title: Text(l10n.searchCurrentLocation),
                              subtitle: Text(
                                locating
                                    ? l10n.searchGettingLocation
                                    : (userLoc.hasFix
                                        ? l10n.searchUsingGps
                                        : (userLoc.resolveFinished
                                            ? l10n.searchTapToRetryLocation
                                            : l10n.searchGettingLocation)),
                                style: TextStyle(
                                  color: userLoc.hasFix && !locating
                                      ? scheme.onSurfaceVariant
                                      : scheme.onSurfaceVariant.withValues(
                                          alpha: 0.7,
                                        ),
                                ),
                              ),
                              enabled: !_pickingGps,
                              onTap: _pickingGps ? null : _pickCurrentLocation,
                            );
                          }
                          if (_results.isEmpty) {
                            final q = _queryCtrl.text.trim();
                            final msg = q.isEmpty
                                ? l10n.searchNoNearbyStops
                                : l10n.searchNoMatches;
                            return ListTile(
                              title: Text(
                                msg,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                              enabled: false,
                            );
                          }
                          final station = _results[index - 1];
                          final distanceSubtitle = userLoc.hasFix
                              ? formatDistanceAwayFromUser(
                                  stopSuggestionDistanceMeters(
                                    userLoc.lat!,
                                    userLoc.lon!,
                                    station.lat,
                                    station.lon,
                                  ),
                                )
                              : (userLoc.resolveFinished
                                  ? l10n.searchEnableLocationForDistance
                                  : l10n.searchWaitingForGps);
                          return ListTile(
                            leading:
                                const Icon(Icons.location_on_outlined),
                            title: Text(station.name),
                            subtitle: Text(distanceSubtitle),
                            onTap: () => Navigator.of(context).pop(
                              _StationSelectionResult(station: station),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationSelectionResult {
  const _StationSelectionResult({
    this.station,
    this.pickOnMap = false,
  });

  final StopSearchItem? station;
  final bool pickOnMap;
}
