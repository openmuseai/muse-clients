import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_host/main.dart';

void main() {
  testWidgets('launch paints a spinner before the workspace is ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      OpenMuseLaunchApp(boot: () => Completer<Widget>().future),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('launch shows a boot error instead of staying blank', (
    tester,
  ) async {
    await tester.pumpWidget(
      OpenMuseLaunchApp(
        boot: () async => throw StateError('workspace missing'),
      ),
    );
    await tester.pump();
    expect(find.textContaining('无法启动 OpenMuse'), findsOneWidget);
    expect(find.textContaining('workspace missing'), findsOneWidget);
  });
}
