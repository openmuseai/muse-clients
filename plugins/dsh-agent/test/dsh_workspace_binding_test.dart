import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dsh_plugin/src/dsh_workspace_binding.dart';
import 'package:openmuse_dsh_plugin/src/dsh_web_view.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'binding mirrors mount changes without device paths in document',
    () async {
      final root = await Directory.systemTemp.createTemp('openmuse-binding-');
      addTearDown(() => root.delete(recursive: true));
      final first = Directory(p.join(root.path, 'first'))..createSync();
      final second = Directory(p.join(root.path, 'second'))..createSync();
      final home = p.join(root.path, 'dsh');
      var mounts = [
        {'path': first.path, 'name': 'first'},
      ];
      final context = OpenMusePluginContext(
        executeHostCommand: (command, _) async => {
          'workspaceRef': 'openmuse.local.default',
          'title': 'Project Workspace',
          'activeMountPath': mounts.last['path'],
          'dshHome': home,
          'mounts': mounts,
        },
      );
      final binding = DshWorkspaceBinding(context);
      await binding.publish();
      final file = File(p.join(home, 'bindings', 'workspace-binding.json'));
      final firstDocument = jsonDecode(await file.readAsString()) as Map;
      expect(firstDocument['protocol'], 'muse.workspace/binding/v1');
      expect(firstDocument['bindingRevision'], 1);
      expect(await file.readAsString(), isNot(contains(first.path)));
      final firstRef = (firstDocument['mounts'] as List).single['mountRef'];
      expect(
        await File(
          p.join(home, 'bindings', 'materialized', '$firstRef.path'),
        ).readAsString(),
        '${first.path}\n',
      );

      mounts = [
        {'path': first.path, 'name': 'first'},
        {'path': second.path, 'name': 'second'},
      ];
      await binding.publish();
      final updated = jsonDecode(await file.readAsString()) as Map;
      expect(updated['bindingRevision'], 2);
      expect((updated['mounts'] as List), hasLength(2));
      expect(
        updated['activeMountRef'],
        (updated['mounts'] as List).last['mountRef'],
      );
      mounts = [
        {'path': second.path, 'name': 'second'},
      ];
      await binding.publish();
      final pruned = jsonDecode(await file.readAsString()) as Map;
      expect((pruned['mounts'] as List), hasLength(1));
      expect(
        await File(
          p.join(home, 'bindings', 'materialized', '$firstRef.path'),
        ).exists(),
        isFalse,
      );
    },
  );

  test('DSH resource open envelope validates path and type', () {
    final valid = DshResourceOpenMessage.parse(
      jsonEncode({
        'type': 'resource.open',
        'path': 'script.sh',
        'cwd': '/workspace',
        'line': 7,
      }),
    );
    expect(valid.path, 'script.sh');
    expect(valid.line, 7);
    expect(
      () => DshResourceOpenMessage.parse('{"type":"unknown"}'),
      throwsFormatException,
    );
    expect(
      () => DshResourceOpenMessage.parse({
        'type': 'resource.open',
        'path': '../x',
        'cwd': '',
      }),
      throwsFormatException,
    );
  });
}
