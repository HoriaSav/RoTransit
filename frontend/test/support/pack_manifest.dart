import 'dart:convert';
import 'dart:io';

/// pack_version from the bundled manifest (read from disk, independent of
/// the app code under test).
String bundledPackVersion() {
  final manifest = jsonDecode(
    File('assets/data/brasov_companion.manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return manifest['pack_version'] as String;
}

String bundledDataAsOf() {
  final manifest = jsonDecode(
    File('assets/data/brasov_companion.manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return manifest['data_as_of'] as String;
}
