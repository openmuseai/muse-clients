import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dsh_plugin/openmuse_dsh_plugin.dart';
import 'package:openmuse_dsh_plugin/src/dsh_workspace_sync.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

void main() {
  test(
    'Host mounts are adopted in DSH order and repeated updates are deduplicated',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final calls = <String>[];
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final method = body['method'] as String;
        final payload = body['payload'] as Map;
        calls.add('$method:$payload');
        final value = method == 'workspace.create'
            ? {
                'workspace': {'workspaceId': payload['path']},
              }
            : {'workspaceIds': const <String>[]};
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'type': 'server-response',
            'rpcId': body['rpcId'],
            'result': {'ok': true, 'value': value},
          }),
        );
        await request.response.close();
      });
      var active = '/tmp/openmuse-two';
      final context = OpenMusePluginContext(
        executeHostCommand: (command, _) async {
          expect(command, 'workspace.snapshot');
          return {
            'activeMountPath': active,
            'mounts': [
              {'path': '/tmp/openmuse-one'},
              {'path': '/tmp/openmuse-two'},
            ],
          };
        },
      );
      final sync = DshWorkspaceSynchronizer(
        context: context,
        endpoint: () => Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      await sync.sync();
      expect(
        calls.where((value) => value.startsWith('workspace.create')),
        hasLength(2),
      );
      expect(calls.first, contains('/tmp/openmuse-two'));
      expect(calls.last, contains('workspace.insertBefore'));
      await sync.sync();
      expect(calls, hasLength(3));
      active = '/tmp/openmuse-one';
      await sync.sync();
      expect(calls, hasLength(6));
      expect(calls[3], contains('/tmp/openmuse-one'));
    },
  );

  test(
    'latest DSH adopts a Host mount without an API key',
    () async {
      final root = await Directory.systemTemp.createTemp('openmuse-dsh-sync-');
      final mount = Directory('${root.path}/project');
      await mount.create();
      final supervisor = DshSidecarSupervisor(
        environment: {
          'OPENMUSE_DSH_CLI': Platform.environment['OPENMUSE_DSH_CLI']!,
          'DSH_HOME': '${root.path}/dsh',
          'DEEPSEEK_API_KEY': '',
        },
      );
      try {
        await supervisor.ensureStarted();
        final sync = DshWorkspaceSynchronizer(
          context: OpenMusePluginContext(
            executeHostCommand: (_, _) async => {
              'activeMountPath': mount.path,
              'mounts': [
                {'path': mount.path},
              ],
            },
          ),
          endpoint: () => supervisor.endpoint,
        );
        await sync.sync();
        final client = HttpClient();
        try {
          final request = await client.postUrl(
            supervisor.endpoint!.resolve('/api/workspace.list'),
          );
          request.headers.contentType = ContentType.json;
          request.write(
            jsonEncode({
              'type': 'client-request',
              'rpcId': 'openmuse-sync-test',
              'method': 'workspace.list',
              'payload': {},
            }),
          );
          final response = await request.close();
          final body =
              jsonDecode(await utf8.decoder.bind(response).join()) as Map;
          final items =
              ((body['result'] as Map)['value'] as Map)['items'] as List;
          expect(
            items.any(
              (item) => (item as Map)['path'].toString().endsWith('/project'),
            ),
            isTrue,
          );
        } finally {
          client.close(force: true);
        }
      } finally {
        await supervisor.stop();
        supervisor.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: Platform.environment['OPENMUSE_DSH_CLI'] == null,
  );
}
