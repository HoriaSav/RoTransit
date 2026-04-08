import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../routes/data/route_api_repository.dart';
import '../../routes/data/local_saved_routes_repository.dart';
import '../../routes/domain/route_models.dart';

class SavedTripDetailsScreen extends ConsumerWidget {
  const SavedTripDetailsScreen({super.key, required this.journey});

  final SavedJourneyVm journey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final validationFuture =
        (journey.remoteRouteId != null && journey.deviceUserId != null)
            ? ref.read(routeApiRepositoryProvider).validateSavedRoute(
                  routeId: journey.remoteRouteId!,
                  deviceUserId: journey.deviceUserId!,
                  serviceDateTime: DateTime.now(),
                )
            : Future.value(
                const SavedRouteValidation(
                  isValid: false,
                  reason: 'Validation unavailable (local-only route)',
                ),
              );
    return Scaffold(
      appBar: AppBar(title: const Text('Trip details')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<SavedRouteValidation>(
              future: validationFuture,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const LinearProgressIndicator(minHeight: 3);
                }
                final validation = snap.data!;
                final valid = validation.isValid;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: valid
                        ? Colors.green.withValues(alpha: 0.14)
                        : Colors.orange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valid
                        ? 'Route is still valid'
                        : 'Route may no longer be valid: ${validation.reason}',
                  ),
                );
              },
            ),
            Text(
              '${(journey.route.durationSeconds / 60).round()} min',
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(height: 12),
            const Text('Steps', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            for (final leg in journey.route.legs)
              Text('• ${leg.mode} ${leg.fromName} -> ${leg.toName}'),
          ],
        ),
      ),
    );
  }
}
