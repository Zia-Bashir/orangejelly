import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled app fonts so widget tests lay out with real metrics
/// instead of the wide default test font.
Future<void> loadAppFonts() async {
  const fonts = {
    'InstrumentSerif': [
      'assets/fonts/InstrumentSerif-Regular.ttf',
      'assets/fonts/InstrumentSerif-Italic.ttf',
    ],
    'PlexMono': [
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
    ],
    'Inter': ['assets/fonts/Inter.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}
