import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_extra_colors.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/state/navigation_provider.dart';
import '../data/companion_catalog.dart';
import 'stop_board_sheet.dart';

/// Focus map camera on a companion stop (watched by [MapTab]).
final companionFocusStopProvider =
    StateProvider<StopSearchItem?>((ref) => null);

/// Map tab chrome: station search over the live map (companion, not a router).
class MapCompanionTab extends ConsumerStatefulWidget {
  const MapCompanionTab({super.key});

  @override
  ConsumerState<MapCompanionTab> createState() => _MapCompanionTabState();
}

class _MapCompanionTabState extends ConsumerState<MapCompanionTab> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<StopSearchItem> _suggestions = const [];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _onQueryChanged(String value) async {
    final q = value.trim();
    if (q.length < 2) {
      setState(() => _suggestions = const []);
      return;
    }
    setState(() => _searching = true);
    final results =
        await ref.read(companionCatalogProvider).searchStops(q, limit: 12);
    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _searching = false;
    });
  }

  Future<void> _selectStop(StopSearchItem stop) async {
    _controller.text = stop.name;
    setState(() => _suggestions = const []);
    _focus.unfocus();
    ref.read(companionFocusStopProvider.notifier).state = stop;
    ref.read(showMapSheetProvider.notifier).state = false;
    if (!mounted) return;
    await showStopBoardSheet(context, stop: stop);
  }

  @override
  Widget build(BuildContext context) {
    final extra = context.extraColors;
    final scheme = Theme.of(context).colorScheme;
    final topPad = MediaQuery.paddingOf(context).top + 8;

    // Stack with only Positioned chrome: empty areas defer hits to the map
    // underneath. Do NOT wrap in IgnorePointer(ignoring: true) — a parent
    // IgnorePointer blocks the entire subtree; child ignoring:false cannot
    // re-enable the Settings gear / search field.
    return Stack(
      children: [
        Positioned(
          left: 12,
          right: 12,
          top: topPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        elevation: 2,
                        color: extra.floatingNavBackground,
                        borderRadius: BorderRadius.circular(28),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          onChanged: _onQueryChanged,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search Brașov stations',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _controller.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _controller.clear();
                                      setState(() => _suggestions = const []);
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: extra.floatingNavBackground,
                      elevation: 2,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Settings',
                        onPressed: () {
                          ref.read(settingsOpenProvider.notifier).state = true;
                        },
                        icon: Icon(Icons.settings_outlined, color: scheme.primary),
                      ),
                    ),
                  ],
                ),
                if (_searching || _suggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Material(
                    elevation: 3,
                    color: extra.floatingNavBackground,
                    borderRadius: BorderRadius.circular(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: _suggestions.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final s = _suggestions[i];
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.place_outlined,
                                    color: scheme.primary,
                                  ),
                                  title: Text(s.name),
                                  onTap: () => _selectStop(s),
                                );
                              },
                            ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: extra.floatingNavBackground.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Text(
                        'Schedule times · not live GPS',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Helper for MapTab camera moves.
LatLng? companionStopLatLng(StopSearchItem? stop) {
  if (stop == null) return null;
  if (stop.lat == 0 && stop.lon == 0) return null;
  return LatLng(stop.lat, stop.lon);
}
