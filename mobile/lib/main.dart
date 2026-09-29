import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/storage/prefs_storage.dart';
import 'providers/infrastructure_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // SharedPreferences cannot be created synchronously, so it is loaded here
  // and injected — that keeps `prefsStorageProvider` a plain synchronous
  // read everywhere else, including inside the theme provider.
  final PrefsStorage prefs = await PrefsStorage.create();

  runApp(
    ProviderScope(
      overrides: <Override>[
        prefsStorageProvider.overrideWithValue(prefs),
      ],
      child: const SmartQueueApp(),
    ),
  );
}
