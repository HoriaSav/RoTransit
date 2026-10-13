import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

/// Points sqflite at FFI and path_provider's documents dir at a fresh temp
/// directory for each test. Returns a getter for the current temp dir.
Directory Function() usePackTestEnv({String prefix = 'rotransit_test_'}) {
  late Directory tempDocs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp(prefix);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDocs.path;
      }
      // Cache/temp/support dirs (e.g. flutter_map's tile cache) go in a
      // subfolder so they never collide with the documents files.
      if (call.method.endsWith('Directory')) {
        final d = Directory('${tempDocs.path}/_${call.method}')
          ..createSync(recursive: true);
        return d.path;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await tempDocs.exists()) {
      await tempDocs.delete(recursive: true);
    }
  });

  return () => tempDocs;
}
