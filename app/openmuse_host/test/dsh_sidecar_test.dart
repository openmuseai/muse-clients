import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dsh_plugin/openmuse_dsh_plugin.dart';

void main() {
  test('JavaScript CLI is launched through node without a shell', () {
    final command = dshCommand('/tmp/dsh/lib/bin.js', ['--version']);
    expect(command.executable, 'node');
    expect(command.arguments, ['/tmp/dsh/lib/bin.js', '--version']);
    final bundled = dshCommand(
      '/tmp/dsh/lib/bin.js',
      ['--version'],
      nodeExecutable: '/bundle/node/bin/node',
    );
    expect(bundled.executable, '/bundle/node/bin/node');
  });

  test('web sidecar asks DSH itself for an ephemeral loopback port', () {
    final command = dshWebCommand('/tmp/dsh/lib/bin.js');
    expect(command.executable, 'node');
    expect(command.arguments, [
      '/tmp/dsh/lib/bin.js',
      'web',
      '--host',
      '127.0.0.1',
      '--port',
      '0',
    ]);
  });

  test(
    'missing runtime is configuration state, not missing model key',
    () async {
      final supervisor = DshSidecarSupervisor(environment: {});
      await supervisor.ensureStarted();
      expect(supervisor.state, DshSidecarState.configurationRequired);
      expect(supervisor.launchCount, 0);
      supervisor.dispose();
    },
  );

  test('model key is not a launch prerequisite', () async {
    final supervisor = DshSidecarSupervisor(
      environment: {'OPENMUSE_DSH_CLI': '/no/such/dsh-runtime'},
    );
    await expectLater(
      supervisor.ensureStarted(),
      throwsA(isA<ProcessException>()),
    );
    expect(supervisor.state, DshSidecarState.failed);
    supervisor.dispose();
  });

  test('readiness probe accepts a local HTTP endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    });
    await waitForHttp(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      const Duration(seconds: 2),
    );
    await server.close(force: true);
  });

  test(
    'latest CLI starts the local web UI without a model key',
    () async {
      final root = await Directory.systemTemp.createTemp('openmuse-dsh-test-');
      final supervisor = DshSidecarSupervisor(
        environment: {
          'OPENMUSE_DSH_CLI': Platform.environment['OPENMUSE_DSH_CLI']!,
          'DSH_HOME': root.path,
          'DEEPSEEK_API_KEY': '',
        },
      );
      try {
        await supervisor.ensureStarted();
        expect(supervisor.state, DshSidecarState.ready);
        expect(supervisor.endpoint?.host, '127.0.0.1');
      } finally {
        await supervisor.stop();
        supervisor.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: Platform.environment['OPENMUSE_DSH_CLI'] == null,
  );
}
