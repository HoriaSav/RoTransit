import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../../../core/config/api_config.dart';
import '../../../core/location/user_location_helpers.dart';
import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/data/route_api_repository.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
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
          preferredRef: isFrom ? _selectedToStop : _selectedFromStop,
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
      final cities = await ref.read(routeApiRepositoryProvider).getCities();
      if (cities.isEmpty) {
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
      final city = cities.first;
      if (!mounted) return;
      // City bootstrap should succeed even if nearby stops endpoint is unavailable.
      setState(() {
        _cityId = city.id;
        _cityName = city.name;
      });
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: city.id,
            cityName: city.name,
          );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _cityId = null;
        _cityName = 'RoTransit';
      });
      final status = e.response?.statusCode;
      final path = e.requestOptions.path;
      ScaffoldMessenger.of(context).showSnackBar(
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
    ScaffoldMessenger.of(context).showSnackBar(
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

  void _applyRecentSearch(RecentSearchEntry entry) {
    final now = DateTime.now();
    setState(() {
      _cityId = entry.cityId;
      _cityName = entry.cityName;
      _selectedFromStop = entry.fromStop;
      _selectedToStop = entry.toStop;
      _fromCtrl.text = entry.fromStop.name;
      _toCtrl.text = entry.toStop.name;
      _date = DateTime(now.year, now.month, now.day);
      _time = TimeOfDay(hour: now.hour, minute: now.minute);
    });
    ref.read(searchMapStateProvider.notifier).setCityContext(
          cityId: entry.cityId,
          cityName: entry.cityName,
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
    if (_fromCtrl.text.trim().isEmpty ||
        _toCtrl.text.trim().isEmpty ||
        _date == null ||
        _time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete From, To, Date, Time')),
      );
      return;
    }
    if (_cityId == null) {
      await _loadSearchSeedData();
    }
    if (_cityId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not load cities from backend. Check backend/cities endpoint.',
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tap From/To and select both stations from the station picker (or map).',
            ),
          ),
        );
        return;
      }

      final origin = '${fromStop.lat},${fromStop.lon}';
      final String destination;
      if (toStop.stopId.startsWith('map:') || toStop.stopId.startsWith('gps:')) {
        destination = '${toStop.lat},${toStop.lon}';
      } else {
        destination = await ref
            .read(routeApiRepositoryProvider)
            .resolveDestinationForRoute(
              cityId: _cityId!,
              origin: origin,
              stopName: toStop.name,
              serviceDateTime: dt,
              fallbackLat: toStop.lat,
              fallbackLon: toStop.lon,
            );
      }
      final request = RouteSearchRequest(
        cityId: _cityId!,
        origin: origin,
        destination: destination,
        serviceDate: dt,
        serviceTime: dt,
        offset: 0,
        limit: 10,
      );
      final response =
          await ref.read(routeApiRepositoryProvider).search(request);
      final recentFromName = _resolvedRecentFromName(
        selectedFrom: fromStop,
        response: response,
      );
      final recentToName = _resolvedRecentToName(
        selectedTo: toStop,
        response: response,
      );
      ref.read(searchMapStateProvider.notifier).setResults(
            cityId: response.cityId,
            cityName: response.cityName,
            options: response.routes,
            offset: response.offset,
            limit: response.limit,
            total: response.total,
            request: request,
          );
      await ref.read(recentSearchesRepositoryProvider).addRecentSearch(
            cityId: _cityId!,
            cityName: _cityName,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No routes found for selected inputs.')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(full)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Unexpected error while searching routes.')),
      );
    } finally {
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
          _fromCtrl.text = next.value;
          _selectedFromStop = _parseCoordinateSelection(next.value);
        } else {
          _toCtrl.text = next.value;
          _selectedToStop = _parseCoordinateSelection(next.value);
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

    const fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Colors.black, width: 1.6),
    );
    const dateTimeBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Color(0xFFB8C0CC), width: 0.9),
    );
    const fieldStyle = TextStyle(
      color: Colors.black,
      fontSize: 16,
      fontWeight: FontWeight.w500,
    );
    const labelStyle = TextStyle(
      color: Colors.black,
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
                      color: const Color(0xFFFDFEFE).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 14,
                          offset: Offset(0, 4),
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
                            color: Colors.white,
                            shape: const CircleBorder(),
                            elevation: 1.5,
                            child: IconButton(
                              tooltip: 'Swap From and To',
                              onPressed: _swapStations,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.swap_vert_rounded,
                                size: 18,
                                color: Color(0xFF5F6672),
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
                                  color: Colors.black87,
                            ),
                                labelStyle: labelStyle.copyWith(
                                  fontSize: 13,
                                  color: Colors.black54,
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
                                  color: Colors.black87,
                            ),
                                labelStyle: labelStyle.copyWith(
                                  fontSize: 13,
                                  color: Colors.black54,
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
                          backgroundColor: const Color(0xFF0A3E96),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 46),
                          disabledBackgroundColor: const Color(0xFFECF2FF),
                          disabledForegroundColor: const Color(0xFF3F66A8),
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
                          color: Colors.black.withValues(alpha: 0.52),
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    recentSearchesAsync.when(
                      data: (items) {
                        if (items.isEmpty) {
                          return const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'No recent searches yet.',
                              style: TextStyle(color: Colors.black54),
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
                                    color: const Color(0xFFF8FAFC),
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
                                            color: const Color(0xFFE7ECF3),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.history_rounded,
                                              size: 16,
                                              color: Color(0xFF5F6672),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${indexed.value.fromStop.name} -> ${indexed.value.toStop.name}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 13.5),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              indexed.value.serviceTimeLabel,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Colors.black.withValues(alpha: 0.62),
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
                      error: (_, __) => const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Could not load recent searches.',
                          style: TextStyle(color: Colors.black54),
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

  StopSearchItem? _parseCoordinateSelection(String value) {
    final parts = value.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts.first.trim());
    final lon = double.tryParse(parts.last.trim());
    if (lat == null || lon == null) return null;
    return StopSearchItem(
      stopId: 'map:$lat,$lon',
      name: value,
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
              color: Colors.black54,
              fontWeight: FontWeight.w400,
            ),
            border: widget.border,
            enabledBorder: widget.border,
            focusedBorder: widget.border.copyWith(
              borderSide: const BorderSide(color: Color(0xFF0A3E96), width: 2),
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
            borderSide: const BorderSide(color: Color(0xFF0A3E96), width: 1.4),
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
    this.preferredRef,
  });

  final String title;
  final String? cityId;
  final String initialQuery;
  final StopSearchItem? preferredRef;

  @override
  ConsumerState<_StationSearchSheet> createState() =>
      _StationSearchSheetState();
}

class _StationSearchSheetState extends ConsumerState<_StationSearchSheet> {
  late final TextEditingController _queryCtrl;
  Timer? _debounce;
  bool _loading = false;
  List<StopSearchItem> _results = const [];
  /// Resolved once when the sheet opens; null means use [kDefaultSearchRefLat]/Lon.
  /// If [widget.preferredRef] exists, it overrides GPS for stop ranking.
  ({double lat, double lon})? _userRef;

  double get _refLat =>
      widget.preferredRef?.lat ?? _userRef?.lat ?? kDefaultSearchRefLat;
  double get _refLon =>
      widget.preferredRef?.lon ?? _userRef?.lon ?? kDefaultSearchRefLon;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery);
    _queryCtrl.addListener(_onQueryChanged);
    _bootstrapSheet();
  }

  Future<void> _bootstrapSheet() async {
    setState(() => _loading = true);
    final p = await tryGetCurrentUserLatLon();
    if (!mounted) return;
    setState(() => _userRef = p);
    await _loadInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.removeListener(_onQueryChanged);
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    if (widget.cityId == null) return;
    setState(() => _loading = true);
    try {
      final stops = await ref.read(routeApiRepositoryProvider).getNearbyStops(
            cityId: widget.cityId!,
            lat: _refLat,
            lon: _refLon,
            radiusMeters: 5000,
          );
      if (!mounted) return;
      setState(() {
        _results = stops
            .map((e) => StopSearchItem(
                  stopId: e.stopId,
                  name: e.name,
                  lat: e.lat,
                  lon: e.lon,
                ))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
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
      await _loadInitial();
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await ref.read(routeApiRepositoryProvider).searchStops(
            cityId: widget.cityId!,
            query: q,
            limit: 20,
            refLat: _refLat,
            refLon: _refLon,
          );
      if (!mounted) return;
      setState(() => _results = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCurrentLocation() async {
    final pos = await tryGetCurrentUserLatLon();
    if (!mounted) return;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not get your position. Enable location or use Select on map.',
          ),
        ),
      );
      return;
    }
    final latStr = pos.lat.toStringAsFixed(5);
    final lonStr = pos.lon.toStringAsFixed(5);
    Navigator.of(context).pop(
      _StationSelectionResult(
        station: StopSearchItem(
          stopId: 'gps:$latStr,$lonStr',
          name: 'Current location',
          lat: pos.lat,
          lon: pos.lon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                              leading: const Icon(Icons.my_location, color: Colors.black87),
                              title: const Text('Current location'),
                              subtitle: Text(
                                _userRef != null
                                    ? 'Use your GPS position'
                                    : 'Location not available yet',
                                style: TextStyle(
                                  color: _userRef != null
                                      ? Colors.black54
                                      : Colors.black38,
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
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 14,
                                ),
                              ),
                              enabled: false,
                            );
                          }
                          final station = _results[index - 1];
                          final km = _distanceKm(
                            _refLat,
                            _refLon,
                            station.lat,
                            station.lon,
                          );
                          return ListTile(
                            leading:
                                const Icon(Icons.location_on_outlined),
                            title: Text(station.name),
                            subtitle: Text('${km.toStringAsFixed(2)} km'),
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

  double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * math.pi / 180;
}

class _StationSelectionResult {
  const _StationSelectionResult({
    this.station,
    this.pickOnMap = false,
  });

  final StopSearchItem? station;
  final bool pickOnMap;
}
