import 'package:flutter/material.dart';
import 'package:rotransit/l10n/app_localizations.dart';

import '../../../core/theme/app_extra_colors.dart';
import '../../routes/domain/route_models.dart';

/// Full-screen stop chooser with a top back button (replaces DropdownButton).
///
/// Pops with the selected [RouteStop.stopId], or null if dismissed via back.
class TimetableStopPickerPage extends StatelessWidget {
  const TimetableStopPickerPage({
    super.key,
    required this.stops,
    this.selectedStopId,
  });

  final List<RouteStop> stops;
  final String? selectedStopId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final extra = context.extraColors;

    return Scaffold(
      backgroundColor: extra.tabBackground,
      appBar: AppBar(
        backgroundColor: extra.shellHeader,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        leading: IconButton(
          tooltip: l10n.busBack,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(l10n.searchSelectStop),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        itemCount: stops.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: extra.recentTileBorder,
        ),
        itemBuilder: (context, index) {
          final stop = stops[index];
          final selected = stop.stopId == selectedStopId;
          return ListTile(
            selected: selected,
            leading: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            title: Text(
              '${stop.stopSequence}. ${stop.name}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).pop(stop.stopId),
          );
        },
      ),
    );
  }
}
