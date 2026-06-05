import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../../core/format/distance_format.dart';
import '../../../core/location/user_location_helpers.dart';
import '../../../core/location/user_location_provider.dart';
import '../../../core/network/connectivity_status.dart';
import '../../../core/ui/app_snackbar.dart';
import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/data/offline_transit_cache_repository.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/data/stop_suggestion_dedupe.dart';
import '../../routes/domain/route_models.dart';
import '../data/recent_searches_repository.dart';
import '../state/search_quick_access_providers.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';

class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({
    super.key,
    this.bootstrapFromBackend = true,
  });

  final bool bootstrapFromBackend;

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  static const _fallbackCityId = '00000000-0000-0000-0000-000000000001';
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _loading = false;
  String? _cityId;
  String _cityName = 'City';
  StopSearchItem? _selectedFromStop;
  StopSearchItem? _selectedToStop;

  String? _extractBackendErrorCode(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final code = data['code']?.toString();
      if (code != null && code.isNotEmpty) return code;
    }
    return null;
  }

  bool _isCityNotFound(DioException e) {
    final code = _extractBackendErrorCode(e);
    return e.response?.statusCode == 404 && code == 'CITY_NOT_FOUND';
  }

  Future<CityItem?> _resolveBackendCity({
    String? preferredId,
    String? preferredName,
  }) async {
    final cities = await ref.read(routeApiRepositoryProvider).getCities();
    if (cities.isEmpty) return null;
    if (preferredId != null && preferredId.isNotEmpty) {
      for (final city in cities) {
        if (city.id == preferredId) return city;
      }
    }
    if (preferredName != null && preferredName.trim().isNotEmpty) {
      final needle = preferredName.trim().toLowerCase();
      for (final city in cities) {
        if (city.name.trim().toLowerCase() == needle) return city;
      }
    }
    return cities.first;
  }

  Future<bool> _refreshCityContextFromBackend({
    String? preferredId,
    String? preferredName,
  }) async {
    if (!ApiConfig.useBackend) return false;
    final city = await _resolveBackendCity(
      preferredId: preferredId,
      preferredName: preferredName,
    );
    if (city == null) return false;
    if (!mounted) return false;
    setState(() {
      _cityId = city.id;
      _cityName = city.name;
    });
    ref.read(searchMapStateProvider.notifier).setCityContext(
          cityId: city.id,
          cityName: city.name,
        );
    return true;
  }
  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _time = TimeOfDay(hour: now.hour, minute: now.minute);
    if (widget.bootstrapFromBackend) {
      _loadSearchSeedData();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(userLocationProvider.notifier).resolve();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: now,
    );
    if (date != null) setState(() => _date = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) setState(() => _time = time);
  }

  Future<void> _selectStation({required bool isFrom}) async {
    if (_cityId == null) {
      await _loadSearchSeedData();
    }
    if (_cityId == null) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        const SnackBar(
          content: Text('Could not load city context for station selection.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    final initial = isFrom ? _fromCtrl.text : _toCtrl.text;
    final selected = await Navigator.of(context).push<_StationSelectionResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _StationSearchSheet(
          title: isFrom ? 'Departure' : 'Destination',
          cityId: _cityId,
          initialQuery: initial,
        ),
      ),
    );
    if (selected == null) return;
    if (selected.pickOnMap) {
      _startMapPick(isFrom: isFrom);
      return;
    }
    final station = selected.station;
    if (station == null) return;
    setState(() {
      if (isFrom) {
        _fromCtrl.text = station.name;
        _selectedFromStop = station;
      } else {
        _toCtrl.text = station.name;
        _selectedToStop = station;
      }
    });
  }

  Future<void> _loadSearchSeedData() async {
    try {
      final resolved = await _resolveBackendCity(
        preferredId: _cityId,
        preferredName: _cityName,
      );
      if (resolved == null) {
        if (!mounted) return;
        if (ApiConfig.useBackend) {
          setState(() {
            _cityId = null;
            _cityName = 'RoTransit';
          });
        } else {
          setState(() {
            _cityId = _fallbackCityId;
            _cityName = 'Preview mode';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _cityId = resolved.id;
        _cityName = resolved.name;
      });
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: resolved.id,
            cityName: resolved.name,
          );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _cityId = null;
        _cityName = 'RoTransit';
      });
      final status = e.response?.statusCode;
      final path = e.requestOptions.path;
      showAppSnackBar(
        context,
        SnackBar(
          content: Text(
            'City bootstrap failed ($status) on $path at ${ApiConfig.baseUrl}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      if (ApiConfig.useBackend) {
        setState(() {
          _cityId = null;
          _cityName = 'RoTransit';
        });
      } else {
        setState(() {
          _cityId = _fallbackCityId;
          _cityName = 'Preview mode';
        });
      }
    }
  }

  void _startMapPick({required bool isFrom}) {
    ref.read(mapSelectionTargetProvider.notifier).state =
        isFrom ? LocationSelectionTarget.from : LocationSelectionTarget.to;
    showAppSnackBar(
        context,
      SnackBar(
        content: Text(
          'Tap on the map to set ${isFrom ? 'From' : 'To'} location.',
        ),
      ),
    );
  }

  void _swapStations() {
    setState(() {
      final from = _fromCtrl.text;
      _fromCtrl.text = _toCtrl.text;
      _toCtrl.text = from;
      final fromStop = _selectedFromStop;
      _selectedFromStop = _selectedToStop;
      _selectedToStop = fromStop;
    });
  }

  Future<void> _applyRecentSearch(RecentSearchEntry entry) async {
    var resolvedCityId = entry.cityId;
    var resolvedCityName = entry.cityName;
    if (ApiConfig.useBackend) {
      final ok = await _refreshCityContextFromBackend(
        preferredId: entry.cityId,
        preferredName: entry.cityName,
      );
      if (ok && mounted) {
        resolvedCityId = _cityId ?? entry.cityId;
        resolvedCityName = _cityName;
      }
    }
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _cityId = resolvedCityId;
      _cityName = resolvedCityName;
      _selectedFromStop = entry.fromStop;
      _selectedToStop = entry.toStop;
      _fromCtrl.text = entry.fromStop.name;
      _toCtrl.text = entry.toStop.name;
      _date = DateTime(now.year, now.month, now.day);
      _time = TimeOfDay(hour: now.hour, minute: now.minute);
    });
    ref.read(searchMapStateProvider.notifier).setCityContext(
          cityId: resolvedCityId,
          cityName: resolvedCityName,
        );
  }

  void _applyFavoriteJourney(SavedJourneyVm journey) {
    final legs = journey.route.legs;
    if (legs.isEmpty) return;
    final first = legs.first;
    final last = legs.last;
    setState(() {
      _fromCtrl.text = first.fromName;
      _toCtrl.text = last.toName;
      _selectedFromStop = StopSearchItem(
        stopId: 'fav-from:${journey.id}',
        name: first.fromName,
        lat: first.fromLat,
        lon: first.fromLon,
      );
      _selectedToStop = StopSearchItem(
        stopId: 'fav-to:${journey.id}',
        name: last.toName,
        lat: last.toLat,
        lon: last.toLon,
      );
      _date ??= DateTime.now();
      _time ??= TimeOfDay.now();
      _cityId = journey.cityId;
    });
  }

  bool _isCoordinateLikeStop(StopSearchItem stop) {
    final id = stop.stopId.toLowerCase();
    return id.startsWith('map:') || id.startsWith('gps:');
  }

  RouteLeg? _firstTransitLeg(RouteOption option) {
    for (final leg in option.legs) {
      final mode = leg.mode.trim().toUpperCase();
      if (mode != 'WALK' && mode != 'BICYCLE' && mode != 'CAR') {
        return leg;
      }
    }
    return null;
  }

  RouteLeg? _lastTransitLeg(RouteOption option) {
    for (final leg in option.legs.reversed) {
      final mode = leg.mode.trim().toUpperCase();
      if (mode != 'WALK' && mode != 'BICYCLE' && mode != 'CAR') {
        return leg;
      }
    }
    return null;
  }

  String _resolvedRecentFromName({
    required StopSearchItem selectedFrom,
    required RouteSearchResponse response,
  }) {
    if (!_isCoordinateLikeStop(selectedFrom)) return selectedFrom.name;
    if (response.routes.isEmpty) return 'Origin';
    final option = response.routes.first;
    final firstTransit = _firstTransitLeg(option);
    final fallbackLeg = option.legs.isNotEmpty ? option.legs.first : null;
    final candidate = (firstTransit?.fromName ?? fallbackLeg?.fromName ?? '').trim();
    return candidate.isEmpty ? 'Origin' : candidate;
  }

  String _resolvedRecentToName({
    required StopSearchItem selectedTo,
    required RouteSearchResponse response,
  }) {
    if (!_isCoordinateLikeStop(selectedTo)) return selectedTo.name;
    if (response.routes.isEmpty) return 'Destination';
    final option = response.routes.first;
    final lastTransit = _lastTransitLeg(option);
    final fallbackLeg = option.legs.isNotEmpty ? option.legs.last : null;
    final candidate = (lastTransit?.toName ?? fallbackLeg?.toName ?? '').trim();
    return candidate.isEmpty ? 'Destination' : candidate;
  }

  Future<void> _search() async {
    final stopwatch = Stopwatch()..start();
    if (_fromCtrl.text.trim().isEmpty ||
        _toCtrl.text.trim().isEmpty ||
        _date == null ||
        _time == null) {
      showAppSnackBar(
        context,
        const SnackBar(content: Text('Please complete From, To, Date, Time')),
      );
      return;
    }
    if (_cityId == null) {
      await _loadSearchSeedData();
    }
    if (_cityId == null) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Could not load cities from backend. Check backend/cities endpoint.',
          ),
        ),
      );
      return;
    }

    if (!await isDeviceOnline()) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        const SnackBar(
          content: Text('Route search requires an internet connection.'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final dt = DateTime(
        _date!.year,
        _date!.month,
        _date!.day,
        _time!.hour,
        _time!.minute,
      );
      final fromStop = _selectedFromStop;
      final toStop = _selectedToStop;
      if (fromStop == null || toStop == null) {
        if (!mounted) return;
        showAppSnackBar(
        context,
          const SnackBar(
            content: Text(
              'Tap From/To and select both stations from the station picker (or map).',
            ),
          ),
        );
        return;
      }

      Future<RouteSearchResponse> runSearchForCity(String cityId) async {
        final origin = '${fromStop.lat},${fromStop.lon}';
        final isCoordinateDestination = toStop.stopId.startsWith('map:') ||
            toStop.stopId.startsWith('gps:');
        Future<RouteSearchResponse> runWithDestination(String destination) async {
          final request = RouteSearchRequest(
            cityId: cityId,
            origin: origin,
            destination: destination,
            serviceDate: dt,
            serviceTime: dt,
            offset: 0,
            limit: kRouteSearchPageSize,
            includeGeometry: false,
          );
          final response = await ref.read(routeApiRepositoryProvider).search(request);
          ref.read(searchMapStateProvider.notifier).setResults(
                cityId: response.cityId,
                cityName: response.cityName,
                options: response.routes,
                offset: response.offset,
                limit: response.limit,
                total: response.total,
                hasMore: response.hasMore,
                request: request,
              );
          return response;
        }

        final directDestination = '${toStop.lat},${toStop.lon}';
        var response = await runWithDestination(directDestination);
        final shouldTryResolveFallback =
            !isCoordinateDestination && response.routes.isEmpty;
        if (shouldTryResolveFallback) {
          final resolvedDestination = await ref
              .read(routeApiRepositoryProvider)
              .resolveDestinationForRoute(
                cityId: cityId,
                origin: origin,
                stopName: toStop.name,
                serviceDateTime: dt,
                fallbackLat: toStop.lat,
                fallbackLon: toStop.lon,
              );
          if (resolvedDestination != directDestination) {
            response = await runWithDestination(resolvedDestination);
          }
        }
        return response;
      }

      RouteSearchResponse response;
      try {
        response = await runSearchForCity(_cityId!);
      } on DioException catch (e) {
        if (!_isCityNotFound(e)) rethrow;
        final recovered = await _refreshCityContextFromBackend(
          preferredName: _cityName,
        );
        if (!recovered || _cityId == null || _cityId!.isEmpty) rethrow;
        response = await runSearchForCity(_cityId!);
      }

      final recentFromName = _resolvedRecentFromName(
        selectedFrom: fromStop,
        response: response,
      );
      final recentToName = _resolvedRecentToName(
        selectedTo: toStop,
        response: response,
      );
      if (mounted) {
        setState(() {
          _cityId = response.cityId;
          _cityName = response.cityName;
        });
      }
      await ref.read(recentSearchesRepositoryProvider).addRecentSearch(
            cityId: response.cityId,
            cityName: response.cityName,
            fromStop: StopSearchItem(
              stopId: fromStop.stopId,
              name: recentFromName,
              lat: fromStop.lat,
              lon: fromStop.lon,
            ),
            toStop: StopSearchItem(
              stopId: toStop.stopId,
              name: recentToName,
              lat: toStop.lat,
              lon: toStop.lon,
            ),
            serviceDate: dt,
            serviceTimeLabel:
                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
          );
      ref.invalidate(recentSearchesProvider);
      ref.read(routeMapOverlaySuppressedProvider.notifier).state = false;
      ref.read(showMapSheetProvider.notifier).state = true;
      if (response.routes.isEmpty && mounted) {
        showAppSnackBar(
        context,
          const SnackBar(content: Text('No routes found for selected inputs.')),
        );
      }
      if (mounted) {
        debugPrint('SearchTab search completed in ${stopwatch.elapsedMilliseconds}ms');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final requestId = e.response?.headers.value('X-Request-Id');
      final backendCode =
          data is Map<String, dynamic> ? data['code'] as String? : null;
      final msg = switch (status) {
        400 => 'Invalid search parameters. Please review station/date/time.',
        404 => 'City or route resource was not found on backend.',
        502 => 'Routing service is unavailable right now. Try again shortly.',
        _ => 'Could not contact backend. Check API URL and backend status.',
      };
      final suffix = [
        if (backendCode != null && backendCode.isNotEmpty) backendCode,
        if (requestId != null && requestId.isNotEmpty) 'req:$requestId',
      ].join(' ');
      final full = suffix.isEmpty ? msg : '$msg ($suffix)';
      showAppSnackBar(context, SnackBar(content: Text(full)));
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        const SnackBar(
            content: Text('Unexpected error while searching routes.')),
      );
    } finally {
      stopwatch.stop();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SearchMapState>(searchMapStateProvider, (prev, next) {
      if (next.cityId.isEmpty || next.cityId == _cityId) return;
      setState(() {
        _cityId = next.cityId;
        _cityName = next.cityName;
        _fromCtrl.clear();
        _toCtrl.clear();
        _selectedFromStop = null;
        _selectedToStop = null;
      });
    });

    ref.listen<MapPickedLocation?>(mapPickedLocationProvider, (prev, next) {
      if (next == null) return;
      setState(() {
        if (next.target == LocationSelectionTarget.from) {
          _fromCtrl.text = 'Origin';
          _selectedFromStop = _parseCoordinateSelection(
            next.value,
            isFrom: true,
          );
        } else {
          _toCtrl.text = 'Destination';
          _selectedToStop = _parseCoordinateSelection(
            next.value,
            isFrom: false,
          );
        }
      });
      ref.read(mapPickedLocationProvider.notifier).state = null;
    });

    final dateLabel =
        _date == null ? 'Select date' : DateFormat('MMM d, y').format(_date!);
    final timeLabel = _time == null ? 'Select time' : _time!.format(context);
    final canSubmitSearch = _selectedFromStop != null &&
        _selectedToStop != null &&
        _date != null &&
        _time != null;
    final recentSearchesAsync = ref.watch(recentSearchesProvider);

    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;
    final fieldBorder = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(
        color: Theme.of(context).brightness == Brightness.light
            ? Colors.black
            : scheme.outline,
        width: Theme.of(context).brightness == Brightness.light ? 1.6 : 1.2,
      ),
    );
    final dateTimeBorder = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(
        color: scheme.outlineVariant,
        width: 0.9,
      ),
    );
    final fieldStyle = TextStyle(
      color: scheme.onSurface,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    );
    final labelStyle = TextStyle(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottomPad = shellBottomContentPadding(context);
            return SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 8,
                bottom: bottomPad,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - bottomPad,
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: extra.searchFormCard,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: extra.searchFormShadow,
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
                          children: [
                            _StationField(
                              label: 'From',
                              controller: _fromCtrl,
                              onTapPicker: () => _selectStation(isFrom: true),
                              border: fieldBorder,
                              fieldStyle: fieldStyle,
                              labelStyle: labelStyle,
                            ),
                            const SizedBox(height: 8),
                            _StationField(
                              label: 'To',
                              controller: _toCtrl,
                              onTapPicker: () => _selectStation(isFrom: false),
                              border: fieldBorder,
                              fieldStyle: fieldStyle,
                              labelStyle: labelStyle,
                            ),
                          ],
                        ),
                        Positioned(
                          right: -2,
                          top: 38,
                          child: Material(
                            color: extra.swapButtonBackground,
                            shape: const CircleBorder(),
                            elevation: 1.5,
                            shadowColor: scheme.shadow,
                            child: IconButton(
                              tooltip: 'Swap From and To',
                              onPressed: _swapStations,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.swap_vert_rounded,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DateTimeField(
                            label: 'Date',
                            value: dateLabel,
                            onTap: _pickDate,
                            border: dateTimeBorder,
                            valueStyle: fieldStyle.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: scheme.onSurface,
                            ),
                                labelStyle: labelStyle.copyWith(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _DateTimeField(
                            label: 'Time',
                            value: timeLabel,
                            onTap: _pickTime,
                            border: dateTimeBorder,
                            valueStyle: fieldStyle.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: scheme.onSurface,
                            ),
                                labelStyle: labelStyle.copyWith(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 46),
                        ),
                        onPressed: (_loading || !canSubmitSearch) ? null : _search,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'Search',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Recent',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    recentSearchesAsync.when(
                      data: (items) {
                        if (items.isEmpty) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'No recent searches yet.',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final indexed in items.asMap().entries)
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: Duration(milliseconds: 180 + indexed.key * 80),
                                curve: Curves.easeOutCubic,
                                builder: (context, t, child) => Transform.translate(
                                  offset: Offset(0, (1 - t) * 8),
                                  child: Opacity(opacity: t.clamp(0, 1), child: child),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Material(
                                    color: extra.recentTileBackground,
                                    borderRadius: BorderRadius.circular(8),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _applyRecentSearch(indexed.value),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: extra.recentTileBorder,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.history_rounded,
                                              size: 16,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${indexed.value.fromStop.name} -> ${indexed.value.toStop.name}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  color: scheme.onSurface,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              indexed.value.serviceTimeLabel,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: scheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                      loading: () => const Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, __) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Could not load recent searches.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  StopSearchItem? _parseCoordinateSelection(
    String value, {
    required bool isFrom,
  }) {
    final parts = value.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts.first.trim());
    final lon = double.tryParse(parts.last.trim());
    if (lat == null || lon == null) return null;
    return StopSearchItem(
      stopId: 'map:$lat,$lon',
      name: isFrom ? 'Origin' : 'Destination',
      lat: lat,
      lon: lon,
    );
  }
}

class _StationField extends StatefulWidget {
  const _StationField({
    required this.label,
    required this.controller,
    required this.onTapPicker,
    required this.border,
    required this.fieldStyle,
    required this.labelStyle,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onTapPicker;
  final OutlineInputBorder border;
  final TextStyle fieldStyle;
  final TextStyle labelStyle;

  @override
  State<_StationField> createState() => _StationFieldState();
}

class _StationFieldState extends State<_StationField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant _StationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          readOnly: true,
          onTap: widget.onTapPicker,
          style: widget.fieldStyle,
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: widget.labelStyle,
            floatingLabelStyle: widget.labelStyle,
            hintText: 'Select stop',
            hintStyle: widget.fieldStyle.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
            border: widget.border,
            enabledBorder: widget.border,
            focusedBorder: widget.border.copyWith(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.border,
    required this.valueStyle,
    required this.labelStyle,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final OutlineInputBorder border;
  final TextStyle valueStyle;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          labelText: label,
          labelStyle: labelStyle,
          floatingLabelStyle: labelStyle,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1.4,
            ),
          ),
        ),
        child: Text(value, style: valueStyle),
      ),
    );
  }
}

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

    final skipNetwork = ApiConfig.useBackend && !await isDeviceOnline();
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

      final onlineAllowed = !ApiConfig.useBackend || await isDeviceOnline();
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
    final loc = await ref
        .read(userLocationProvider.notifier)
        .resolve(forceFresh: true);
    if (!mounted) return;
    if (!loc.hasFix) {
      final message = await userLocationFailureMessage();
      if (!mounted) return;
      final openSettings = message.contains('Settings');
      showAppSnackBar(
        context,
        SnackBar(
          content: Text(message),
          action: openSettings
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: openUserLocationSettings,
                )
              : null,
        ),
      );
      return;
    }
    final latStr = loc.lat!.toStringAsFixed(5);
    final lonStr = loc.lon!.toStringAsFixed(5);
    Navigator.of(context).pop(
      _StationSelectionResult(
        station: StopSearchItem(
          stopId: 'gps:$latStr,$lonStr',
          name: 'Current location',
          lat: loc.lat!,
          lon: loc.lon!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            label: const Text('Select on map'),
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
                decoration: const InputDecoration(
                  hintText: 'Search station',
                  prefixIcon: Icon(Icons.search),
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
                            return ListTile(
                              leading: Icon(
                                Icons.my_location,
                                color: scheme.onSurface,
                              ),
                              title: const Text('Current location'),
                              subtitle: Text(
                                userLoc.hasFix
                                    ? 'Using your GPS position'
                                    : (userLoc.resolveFinished
                                        ? 'Tap to retry — enable precise location'
                                        : 'Getting your location...'),
                                style: TextStyle(
                                  color: userLoc.hasFix
                                      ? scheme.onSurfaceVariant
                                      : scheme.onSurfaceVariant.withValues(
                                          alpha: 0.7,
                                        ),
                                ),
                              ),
                              onTap: _pickCurrentLocation,
                            );
                          }
                          if (_results.isEmpty) {
                            final q = _queryCtrl.text.trim();
                            final msg = q.isEmpty
                                ? 'No nearby stops. Search above or use Select on map.'
                                : 'No matches for your search. Try another query or Select on map.';
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
                                  ? 'Enable location for distance'
                                  : 'Waiting for GPS...');
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
