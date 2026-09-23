import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_builtin_plugins/openmuse_builtin_plugins.dart';

void main() {
  test('viewer and Helix gate fixtures are valid local files', () async {
    final samples = await OpenMuseDemoWorkspace.create();
    final png = await File(samples.pngPath).readAsBytes();
    expect(png.take(4).toList(), [137, 80, 78, 71]);
    expect(await File(samples.pdfPath).readAsString(), startsWith('%PDF-1.4'));
    expect(await File(samples.firstTextPath).readAsString(), contains('Helix'));
    expect(
      await File(samples.secondTextPath).readAsString(),
      contains('Runtime reuse'),
    );
  });
}
