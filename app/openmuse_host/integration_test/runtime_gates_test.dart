import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_builtin_plugins/openmuse_builtin_plugins.dart';
import 'package:openmuse_dsh_plugin/openmuse_dsh_plugin.dart';
import 'package:openmuse_helix_plugin/openmuse_helix_plugin.dart';
import 'package:openmuse_host/src/host/openmuse_app.dart';
import 'package:openmuse_host/src/host/workspace_controller.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS creates native text and local viewer platform views', (
    tester,
  ) async {
    final samples = await OpenMuseDemoWorkspace.create();
    final registry = _registry();
    await tester.pumpWidget(
      OpenMuseHostApp(
        registry: registry,
        workspace: LocalWorkspaceController(
          rootPath: samples.rootPath,
          initialResources: [
            OpenMuseResource(
              uri: Uri.file(samples.pngPath),
              displayName: 'preview.png',
            ),
            OpenMuseResource(
              uri: Uri.file(samples.pdfPath),
              displayName: 'specification.pdf',
            ),
            OpenMuseResource(
              uri: Uri.file('${samples.rootPath}/platform.native-gate'),
              displayName: 'Native View Gate',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Project Workspace'), findsOneWidget);
    expect(find.text('DSH Agent'), findsOneWidget);

    await tester.tap(find.text('Native View Gate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('preview.png'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('specification.pdf'));
    await tester.pumpAndSettle();
  });

  testWidgets('real Helix PTY keeps one session per open document', (
    tester,
  ) async {
    final executable = resolveHelixExecutable();
    expect(
      File(executable).existsSync(),
      isTrue,
      reason: 'the packaged Helix binary must be discoverable',
    );
    final samples = await OpenMuseDemoWorkspace.create();
    final pool = HelixRuntimePool(executable: executable);
    await pool.openDocument(samples.firstTextPath);
    expect(pool.state, HelixRuntimeState.ready);
    expect(pool.launchCount, 1);
    final firstPid = pool.pid;
    await pool.openDocument(samples.secondTextPath);
    expect(pool.launchCount, 2);
    expect(pool.pid, isNot(firstPid));
    await pool.openDocument(samples.firstTextPath);
    expect(pool.launchCount, 2);
    expect(pool.pid, firstPid);
    await pool.stop();
    pool.dispose();
  });

  testWidgets('real DSH CLI probes without making API key a Host gate', (
    tester,
  ) async {
    final cli = Platform.environment['OPENMUSE_DSH_CLI'];
    expect(cli, isNotNull, reason: 'OPENMUSE_DSH_CLI is required');
    final dshHome = await Directory.systemTemp.createTemp('openmuse-dsh-gate-');
    addTearDown(() => dshHome.delete(recursive: true));
    final supervisor = DshSidecarSupervisor(
      environment: {
        'OPENMUSE_DSH_CLI': cli!,
        'DSH_HOME': dshHome.path,
        'DEEPSEEK_API_KEY': '',
      },
    );
    expect(await supervisor.probeVersion(), isNotEmpty);
    await supervisor.ensureStarted();
    expect(supervisor.state, DshSidecarState.ready);
    expect(supervisor.launchCount, 1);
    await supervisor.stop();
    supervisor.dispose();
  });
}

OpenMusePluginRegistry _registry() {
  final registry = OpenMusePluginRegistry(
    context: OpenMusePluginContext(executeHostCommand: (_, _) async => null),
  );
  for (final plugin in createOpenMuseBuiltInPlugins()) {
    registry.install(plugin);
  }
  return registry;
}
