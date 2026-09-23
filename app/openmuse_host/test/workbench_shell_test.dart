import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_host/src/host/openmuse_app.dart';
import 'package:openmuse_host/src/host/local_settings.dart';
import 'package:openmuse_host/src/host/workspace_controller.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late OpenMusePluginRegistry registry;
  late LocalWorkspaceController workspace;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('openmuse-shell-test-');
    registry = OpenMusePluginRegistry(
      context: OpenMusePluginContext(executeHostCommand: (_, _) async => null),
    );
    workspace = LocalWorkspaceController(
      rootPath: root.path,
      initialResources: [
        OpenMuseResource(
          uri: Uri.file('${root.path}/README.md'),
          displayName: 'README.md',
        ),
        OpenMuseResource(
          uri: Uri.file('${root.path}/preview.png'),
          displayName: 'preview.png',
        ),
      ],
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('search dialog filters and opens a local resource', (
    tester,
  ) async {
    await tester.pumpWidget(
      OpenMuseHostApp(registry: registry, workspace: workspace),
    );

    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('本地资源'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'preview');
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('README.md')),
      findsNothing,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('preview.png')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: dialog, matching: find.text('preview.png')),
    );
    await tester.pumpAndSettle();
    expect(workspace.selected?.displayName, 'preview.png');
  });

  testWidgets('new document dialog is local-only', (tester) async {
    await tester.pumpWidget(
      OpenMuseHostApp(registry: registry, workspace: workspace),
    );

    await tester.tap(find.text('新建文档').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Local Notes');
    expect(find.text('文件会保存在当前本地工作区。'), findsOneWidget);
    expect(find.textContaining('登录'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('settings contain only local product sections', (tester) async {
    await tester.pumpWidget(
      OpenMuseHostApp(registry: registry, workspace: workspace),
    );

    await tester.tap(find.byTooltip('本地设置'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('工作区'), findsWidgets);
    expect(find.text('插件'), findsWidgets);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('账号'), findsNothing);
    expect(find.text('云服务'), findsNothing);
    expect(find.text('协作'), findsNothing);
  });

  testWidgets('theme selection changes the app immediately', (tester) async {
    final settings = OpenMuseLocalSettings();
    await tester.pumpWidget(
      OpenMuseHostApp(
        registry: registry,
        workspace: workspace,
        settings: settings,
      ),
    );
    await tester.tap(find.byTooltip('本地设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('workspace divider changes width through pointer drag', (
    tester,
  ) async {
    final settings = OpenMuseLocalSettings();
    await tester.pumpWidget(
      OpenMuseHostApp(
        registry: registry,
        workspace: workspace,
        settings: settings,
      ),
    );
    final divider = find.byKey(const Key('pane-resizer')).first;
    final start = tester.getCenter(divider);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(42, 0));
    await tester.pump();
    await gesture.up();
    expect(settings.sidebarWidth, greaterThan(250));
  });

  testWidgets('Project Workspace section can collapse independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      OpenMuseHostApp(registry: registry, workspace: workspace),
    );
    // The sidebar labels a workspace with its basename; split('/') is a POSIX
    // assumption that yields the whole path on Windows.
    final label = p.basename(root.path);
    expect(find.text(label), findsOneWidget);
    await tester.tap(find.byKey(const Key('project-workspace-toggle')));
    await tester.pump();
    expect(workspace.projectSectionExpanded, isFalse);
    expect(find.text(label), findsNothing);
  });

  testWidgets('resource menu groups opening and versions into cascades', (
    tester,
  ) async {
    await tester.pumpWidget(
      OpenMuseHostApp(registry: registry, workspace: workspace),
    );
    await tester.tap(find.text('README.md').first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('打开方式'), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
    expect(find.textContaining('使用 Helix'), findsNothing);
    await tester.tap(find.text('打开方式'));
    await tester.pumpAndSettle();
    expect(find.text('iOffice'), findsOneWidget);
    expect(find.text('默认打开方式'), findsOneWidget);
  });
}
