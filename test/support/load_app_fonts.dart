import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Loads the app's bundled variable typefaces into the test font collection.
///
/// Without this, flutter_test resolves 'Inter' and 'PlusJakartaSans' to its
/// fallback test face, whose glyphs are full-em squares. Text then measures far
/// wider than it ever does on a device, and every layout audit reports phantom
/// RenderFlex overflows. Any test that asserts something about size, wrapping or
/// overflow has to call this first or its numbers are fiction.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in const <String, String>{
    'Inter': 'assets/fonts/Inter.ttf',
    'PlusJakartaSans': 'assets/fonts/PlusJakartaSans.ttf',
  }.entries) {
    final ByteData data = await rootBundle.load(entry.value);
    final loader = FontLoader(entry.key)..addFont(Future.value(data));
    await loader.load();
  }

  await _loadMaterialIcons();
}

/// Loads MaterialIcons from the SDK so `Icon` widgets draw their real glyph
/// instead of the empty-box fallback. Only matters for captured screenshots;
/// layout is unaffected because the fallback occupies the same square. Best
/// effort: skipped when FLUTTER_ROOT is absent or the artifact has moved.
Future<void> _loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) return;

  final file = File(
    p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts',
        'MaterialIcons-Regular.otf'),
  );
  if (!file.existsSync()) return;

  final bytes = await file.readAsBytes();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}
