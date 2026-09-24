import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../../../core/branding/operator_branding.dart';
import '../../../core/theme/app_extra_colors.dart';
import '../../../core/format/distance_format.dart';
import '../../../core/location/user_location_helpers.dart';
import '../../../core/location/user_location_provider.dart';
import '../../../core/network/connectivity_status.dart';
import '../../../core/errors/app_user_message.dart';
import '../../../core/ui/user_feedback.dart';
import '../../routes/data/offline_transit_cache_repository.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/data/stop_suggestion_dedupe.dart';
import '../../routes/domain/route_models.dart';
import '../data/recent_searches_repository.dart';
import '../domain/search_query.dart';
import '../state/search_quick_access_providers.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';

part 'search_form_fields.dart';
part 'station_search_sheet.dart';

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
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _loading = false;
  String _cityId = kBrasovCityId;
  String _cityName = kBrasovCityName;
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

  Future<CityItem> _resolveBackendCity({
    String? preferredId,
    String? preferredName,
  }) async {
    final cities = await ref.read(routeApiRepositoryProvider).getCities();
    return resolveCatalogCity(
      cities,
      preferredId: preferredId,
      preferredName: preferredName,
    );
  }

  void _applyCity(CityItem city) {
    if (!mounted) return;
    setState(() {
      _cityId = city.id;
      _cityName = city.name;
    });
    ref.read(searchMapStateProvider.notifier).setCityContext(
          cityId: city.id,
          cityName: city.name,
        );
  }

  Future<bool> _refreshCityContextFromBackend({
    String? preferredId,
    String? preferredName,
  }) async {
    final city = await _resolveBackendCity(
      preferredId: preferredId,
      preferredName: preferredName,
    );
    if (!mounted) return false;
    _applyCity(city);
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
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: _cityId,
            cityName: _cityName,
          );
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
    if (_cityId.isEmpty) {
      await _loadSearchSeedData();
    }
    if (_cityId.isEmpty) {
      if (!mounted) return;
      showUserMessage(context, AppUserMessages.cityContextUnavailable);
      return;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final initial = isFrom ? _fromCtrl.text : _toCtrl.text;
    final selected = await Navigator.of(context).push<_StationSelectionResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _StationSearchSheet(
          title: isFrom ? l10n.searchDeparture : l10n.searchDestination,
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
      if (!mounted) return;
      _applyCity(resolved);
    } on DioException catch (e) {
      if (!mounted) return;
      _applyCity(kBrasovCityItem);
      showUserError(context, e);
    } catch (_) {
      if (!mounted) return;
      _applyCity(kBrasovCityItem);
    }
  }

  void _startMapPick({required bool isFrom}) {
    ref.read(mapSelectionTargetProvider.notifier).state =
        isFrom ? LocationSelectionTarget.from : LocationSelectionTarget.to;
    showUserMessage(context, AppUserMessages.mapPickHint);
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
    final ok = await _refreshCityContextFromBackend(
      preferredId: entry.cityId,
      preferredName: entry.cityName,
    );
    if (ok && mounted) {
      resolvedCityId = _cityId;
      resolvedCityName = _cityName;
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
    required AppLocalizations l10n,
  }) {
    if (!_isCoordinateLikeStop(selectedFrom)) return selectedFrom.name;
    if (response.routes.isEmpty) return l10n.origin;
    final option = response.routes.first;
    final firstTransit = _firstTransitLeg(option);
    final fallbackLeg = option.legs.isNotEmpty ? option.legs.first : null;
    final candidate = (firstTransit?.fromName ?? fallbackLeg?.fromName ?? '').trim();
    return candidate.isEmpty ? l10n.origin : candidate;
  }

  String _resolvedRecentToName({
    required StopSearchItem selectedTo,
    required RouteSearchResponse response,
    required AppLocalizations l10n,
  }) {
    if (!_isCoordinateLikeStop(selectedTo)) return selectedTo.name;
    if (response.routes.isEmpty) return l10n.destination;
    final option = response.routes.first;
    final lastTransit = _lastTransitLeg(option);
    final fallbackLeg = option.legs.isNotEmpty ? option.legs.last : null;
    final candidate = (lastTransit?.toName ?? fallbackLeg?.toName ?? '').trim();
    return candidate.isEmpty ? l10n.destination : candidate;
  }

  Future<void> _search() async {
    final stopwatch = Stopwatch()..start();
    if (_fromCtrl.text.trim().isEmpty ||
        _toCtrl.text.trim().isEmpty ||
        _date == null ||
        _time == null) {
      showUserMessage(context, AppUserMessages.completeSearchFields);
      return;
    }
    if (_cityId.isEmpty) {
      await _loadSearchSeedData();
    }
    if (_cityId.isEmpty) {
      if (!mounted) return;
      showUserMessage(context, AppUserMessages.cityContextUnavailable);
      return;
    }

    if (!await isDeviceOnline()) {
      if (!mounted) return;
      showUserMessage(context, AppUserMessages.searchRequiresInternet);
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
        showUserMessage(context, AppUserMessages.selectStationsFromPicker);
        return;
      }

      Future<RouteSearchResponse> runSearchForCity(String cityId) async {
        final origin = latLonPoint(fromStop.lat, fromStop.lon);
        final isCoordinateDestination = isCoordinatePickedStop(toStop);
        Future<RouteSearchResponse> runWithDestination(String destination) async {
          final request = buildRouteSearchRequest(
            cityId: cityId,
            origin: origin,
            destination: destination,
            serviceDateTime: dt,
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

        final directDestination = latLonPoint(toStop.lat, toStop.lon);
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
        response = await runSearchForCity(_cityId);
      } on DioException catch (e) {
        if (!_isCityNotFound(e)) rethrow;
        final recovered = await _refreshCityContextFromBackend(
          preferredName: _cityName,
        );
        if (!recovered || _cityId.isEmpty) rethrow;
        response = await runSearchForCity(_cityId);
      }

      final recentFromName = _resolvedRecentFromName(
        selectedFrom: fromStop,
        response: response,
        l10n: AppLocalizations.of(context),
      );
      final recentToName = _resolvedRecentToName(
        selectedTo: toStop,
        response: response,
        l10n: AppLocalizations.of(context),
      );
      ref.read(searchMapStateProvider.notifier).setJourneyLabels(
            originLabel: recentFromName,
            destinationLabel: recentToName,
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
        showUserMessage(context, AppUserMessages.noRoutesFound);
      }
      if (mounted) {
        debugPrint('SearchTab search completed in ${stopwatch.elapsedMilliseconds}ms');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      showUserError(context, e);
    } catch (_) {
      if (!mounted) return;
      showUserMessage(context, AppUserMessages.unexpectedError);
    } finally {
      stopwatch.stop();
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
          _fromCtrl.text = l10n.origin;
          _selectedFromStop = _parseCoordinateSelection(
            next.value,
            isFrom: true,
            l10n: l10n,
          );
        } else {
          _toCtrl.text = l10n.destination;
          _selectedToStop = _parseCoordinateSelection(
            next.value,
            isFrom: false,
            l10n: l10n,
          );
        }
      });
      ref.read(mapPickedLocationProvider.notifier).state = null;
    });

    final dateLabel =
        _date == null ? l10n.searchSelectDate : DateFormat('MMM d, y').format(_date!);
    final timeLabel = _time == null ? l10n.searchSelectTime : _time!.format(context);
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
                              label: l10n.searchFrom,
                              hintText: l10n.searchSelectStop,
                              controller: _fromCtrl,
                              onTapPicker: () => _selectStation(isFrom: true),
                              border: fieldBorder,
                              fieldStyle: fieldStyle,
                              labelStyle: labelStyle,
                            ),
                            const SizedBox(height: 8),
                            _StationField(
                              label: l10n.searchTo,
                              hintText: l10n.searchSelectStop,
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
                              tooltip: l10n.searchSwapTooltip,
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
                            label: l10n.searchDate,
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
                            label: l10n.searchTime,
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
                            : Text(
                                l10n.searchButton,
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
                        l10n.searchRecent,
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
                              l10n.searchNoRecent,
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
                          l10n.searchCouldNotLoadRecent,
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
    required AppLocalizations l10n,
  }) {
    final parts = value.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts.first.trim());
    final lon = double.tryParse(parts.last.trim());
    if (lat == null || lon == null) return null;
    if (!isUsableLatLon(lat, lon)) return null;
    return StopSearchItem(
      stopId: coordinateStopId(kind: 'map', lat: lat, lon: lon),
      name: isFrom ? l10n.origin : l10n.destination,
      lat: lat,
      lon: lon,
    );
  }
}

