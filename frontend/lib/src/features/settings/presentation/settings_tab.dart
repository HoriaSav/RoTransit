import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/state/transport_settings_provider.dart';
import '../../../core/state/theme_mode_provider.dart';
import '../../routes/data/route_api_repository.dart';
import '../../routes/domain/route_models.dart';
import '../../shell/shell_layout.dart';
import '../../shell/state/navigation_provider.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  bool _notifications = true;
  String _version = '1.0';
  bool _isMapDownloading = false;
  double? _mapDownloadProgress;
  String _mapDownloadLabel = 'Not downloaded';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = info.version);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final teEnabled = ref.watch(teTransportEnabledProvider);
    final cityName = ref.watch(
      searchMapStateProvider.select(
        (s) => s.cityName.trim().isEmpty ? 'Brasov' : s.cityName,
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: const Color(0xFFF2F2F2),
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              shellBottomContentPadding(context),
            ),
            children: [
          const Text(
            'Settings',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.location_city_rounded),
                  title: const Text('City'),
                  subtitle: Text(cityName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickCity,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _notifications,
                  title: const Text('Notifications'),
                  onChanged: (value) => setState(() => _notifications = value),
                ),
                SwitchListTile(
                  value: isDark,
                  title: const Text('Dark mode'),
                  onChanged: (value) =>
                      ref.read(themeModeProvider.notifier).setDarkMode(value),
                ),
                SwitchListTile(
                  value: teEnabled,
                  title: const Text('TE transport'),
                  onChanged: (value) => ref
                      .read(teTransportEnabledProvider.notifier)
                      .setEnabled(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Offline map (Brasov area)'),
                  subtitle: Text(_mapDownloadLabel),
                  trailing: _isMapDownloading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  onTap:
                      _isMapDownloading ? null : _confirmAndDownloadOfflineMap,
                ),
                if (_mapDownloadProgress != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: LinearProgressIndicator(value: _mapDownloadProgress),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Version'),
                  trailing: Text(_version),
                ),
                const Divider(height: 1),
                const ListTile(
                  title: Text('Privacy policy'),
                  trailing: Icon(Icons.chevron_right),
                ),
                const Divider(height: 1),
                const ListTile(
                  title: Text('Terms of use'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Column(
              children: [
                ListTile(
                  title: Text('Help'),
                  trailing: Icon(Icons.chevron_right),
                ),
                Divider(height: 1),
                ListTile(
                  title: Text('Contact us'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndDownloadOfflineMap() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Download map for offline use?'),
          content: const Text(
            'This downloads the Brasov map area for offline viewing. '
            'It may use significant storage and network data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Download'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _downloadOfflineMap();
  }

  Future<void> _downloadOfflineMap() async {
    const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    const store = FMTCStore('rotransit_osm_cache');
    setState(() {
      _isMapDownloading = true;
      _mapDownloadProgress = 0;
      _mapDownloadLabel = 'Starting...';
    });

    try {
      await store.manage.create();
      final region = RectangleRegion(
        LatLngBounds(
          const LatLng(45.45, 25.30),
          const LatLng(45.78, 25.82),
        ),
      ).toDownloadable(
        minZoom: 10,
        maxZoom: 16,
        options: TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'com.example.rotransit_frontend',
        ),
      );

      final streams = store.download.startForeground(
        region: region,
        parallelThreads: 4,
        maxBufferLength: 120,
        skipExistingTiles: true,
      );

      final sub = streams.downloadProgress.listen((progress) {
        if (!mounted) return;
        setState(() {
          _mapDownloadProgress = progress.percentageProgress / 100;
          _mapDownloadLabel =
              'Downloading ${progress.percentageProgress.toStringAsFixed(0)}%';
        });
      });

      await streams.downloadProgress.last;
      await sub.cancel();
      if (!mounted) return;
      setState(() {
        _isMapDownloading = false;
        _mapDownloadProgress = null;
        _mapDownloadLabel = 'Downloaded';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline map download completed.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isMapDownloading = false;
        _mapDownloadProgress = null;
        _mapDownloadLabel = 'Download failed';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
          const SnackBar(content: Text('Offline map download failed.')));
    }
  }

  Future<void> _pickCity() async {
    try {
      final cities = await ref.read(routeApiRepositoryProvider).getCities();
      if (!mounted || cities.isEmpty) return;
      final selectedId = ref.read(searchMapStateProvider).cityId;
      final picked = await showModalBottomSheet<CityItem>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView.separated(
            itemCount: cities.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final city = cities[index];
              final isSelected = city.id == selectedId;
              return ListTile(
                title: Text(city.name),
                subtitle:
                    city.country.isEmpty ? null : Text('Country: ${city.country}'),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Color(0xFF0A3E96))
                    : null,
                onTap: () => Navigator.of(context).pop(city),
              );
            },
          ),
        ),
      );
      if (picked == null) return;
      ref.read(searchMapStateProvider.notifier).setCityContext(
            cityId: picked.id,
            cityName: picked.name,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('City changed to ${picked.name}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load cities.')),
      );
    }
  }
}
