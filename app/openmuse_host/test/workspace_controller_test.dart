import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_host/src/host/workspace_controller.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:openmuse_helix_plugin/openmuse_helix_plugin.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('openmuse-workspace-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('search is local and case insensitive', () {
    final controller = LocalWorkspaceController(
      rootPath: root.path,
      initialResources: [
        OpenMuseResource(
          uri: Uri.file('${root.path}/Architecture.md'),
          displayName: 'Architecture.md',
        ),
        OpenMuseResource(
          uri: Uri.file('${root.path}/preview.png'),
          displayName: 'preview.png',
        ),
      ],
    );

    expect(controller.search('ARCH'), hasLength(1));
    expect(controller.search('ARCH').single.displayName, 'Architecture.md');
  });

  test(
    'external filesystem changes refresh mounted Workspace entries',
    () async {
      final controller = LocalWorkspaceController(
        rootPath: root.path,
        initialResources: const [],
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final script = File('${root.path}/fresh.sh');
      await script.writeAsString('#!/bin/sh\necho ready\n');
      final deadline = DateTime.now().add(const Duration(seconds: 4));
      while (controller.search('fresh.sh').isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(controller.search('fresh.sh'), hasLength(1));

      await script.delete();
      while (controller.search('fresh.sh').isNotEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(controller.search('fresh.sh'), isEmpty);
    },
  );

  test('new Markdown is sanitized, persisted, and selected', () async {
    final controller = LocalWorkspaceController(
      rootPath: root.path,
      initialResources: const [],
    );

    final created = await controller.createMarkdown('Roadmap/2027.md');

    expect(created.displayName, 'Roadmap-2027.md');
    expect(controller.selected?.uri, created.uri);
    expect(
      await File.fromUri(created.uri).readAsString(),
      '# Roadmap-2027\n\n',
    );
  });

  test('workspace sidebar and favorite state can be toggled', () {
    final resource = OpenMuseResource(
      uri: Uri.file('${root.path}/README.md'),
      displayName: 'README.md',
    );
    final controller = LocalWorkspaceController(
      rootPath: root.path,
      initialResources: [resource],
    );

    controller.toggleFavorite(resource);
    controller.toggleSidebar();

    expect(controller.isFavorite(resource), isTrue);
    expect(controller.sidebarVisible, isFalse);
  });

  test('real workspace tree loads directories lazily', () async {
    final nested = Directory('${root.path}/src');
    await nested.create();
    await File('${nested.path}/main.dart').writeAsString('void main() {}');
    final controller = LocalWorkspaceController(
      rootPath: root.path,
      initialResources: const [],
    );

    await controller.initialize();
    final directory = controller.mounts.single.root.children.single;
    expect(directory.name, 'src');
    expect(directory.children, isEmpty);

    await controller.toggleDirectory(directory);
    expect(directory.expanded, isTrue);
    expect(directory.children.single.name, 'main.dart');
  });

  test('project and mount collapse preserve expanded folder state', () async {
    final nested = Directory('${root.path}/src');
    await nested.create();
    await File('${nested.path}/script.sh').writeAsString('#!/bin/sh\n');
    final controller = LocalWorkspaceController(
      rootPath: root.path,
      initialResources: const [],
    );
    await controller.initialize();
    final mount = controller.mounts.single;
    final folder = mount.root.children.single;
    await controller.toggleDirectory(folder);
    expect(controller.visibleEntries(mount), hasLength(2));
    await controller.toggleDirectory(mount.root);
    expect(controller.visibleEntries(mount), isEmpty);
    await controller.toggleDirectory(mount.root);
    expect(controller.visibleEntries(mount), hasLength(2));
    await controller.refreshDirectory(mount.root);
    expect(mount.root.children.single, same(folder));
    expect(folder.expanded, isTrue);
    controller.toggleProjectSection();
    expect(controller.projectSectionExpanded, isFalse);
  });

  test('sidecar open is contained within mounted workspace', () async {
    final inside = File('${root.path}/script.sh');
    await inside.writeAsString('#!/bin/sh\n');
    final outside = await Directory.systemTemp.createTemp('openmuse-outside-');
    addTearDown(() => outside.delete(recursive: true));
    final other = File('${outside.path}/secret.txt');
    await other.writeAsString('secret');
    final controller = LocalWorkspaceController(
      rootPath: root.path,
      initialResources: const [],
    );
    final opened = await controller.openHostResource(
      requestedPath: 'script.sh',
      cwd: root.path,
    );
    expect(opened.displayName, 'script.sh');
    expect(controller.selected?.uri, opened.uri);
    await expectLater(
      controller.openHostResource(requestedPath: other.path),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('shell scripts are routed to the Helix plugin', () {
    final registry = OpenMusePluginRegistry(
      context: OpenMusePluginContext(executeHostCommand: (_, _) async => null),
    );
    registry.install(OpenMuseHelixPlugin());
    final resource = OpenMuseResource(
      uri: Uri.file('${root.path}/script.sh'),
      displayName: 'script.sh',
    );
    expect(registry.editorCandidates(resource).first.editor.id, 'helix.editor');
  });

  test(
    'rename retargets an open tab and directory delete closes descendants',
    () async {
      final folder = Directory('${root.path}/src');
      await folder.create();
      final file = File('${folder.path}/old.sh');
      await file.writeAsString('echo ok\n');
      final controller = LocalWorkspaceController(
        rootPath: root.path,
        initialResources: const [],
      );
      await controller.initialize();
      final directoryEntry = controller.mounts.single.root.children.single;
      await controller.toggleDirectory(directoryEntry);
      final fileEntry = directoryEntry.children.single;
      controller.openResource(fileEntry.resource);
      await controller.renameEntry(fileEntry, 'new.sh');
      expect(controller.activeTab?.title, 'new.sh');
      expect(await File('${folder.path}/new.sh').exists(), isTrue);
      await controller.deleteEntry(directoryEntry);
      expect(controller.tabs, isEmpty);
    },
  );

  test('resource tabs are reused and can be closed', () {
    final resource = OpenMuseResource(
      uri: Uri.file('${root.path}/README.md'),
      displayName: 'README.md',
    );
    final controller = LocalWorkspaceController(
      rootPath: root.path,
      initialResources: [resource],
    );

    controller.openResource(resource);
    controller.openResource(resource, editorId: 'helix.editor');
    expect(controller.tabs, hasLength(1));
    expect(controller.activeTab?.preferredEditorId, 'helix.editor');

    controller.closeTab(controller.tabs.single);
    expect(controller.tabs, isEmpty);
    expect(controller.selected, isNull);
  });

  test('content addressed versions open a diff tab', () async {
    final file = File('${root.path}/README.md');
    await file.writeAsString('before\n');
    final resource = OpenMuseResource(uri: file.uri, displayName: 'README.md');
    final controller = LocalWorkspaceController(
      rootPath: root.path,
      initialResources: [resource],
      versionStore: LocalVersionStore(Directory('${root.path}/.versions-test')),
    );

    final snapshot = await controller.captureVersion(resource);
    await file.writeAsString('before\nafter\n');
    await controller.openDiff(resource, snapshot);

    expect(controller.activeTab?.kind, WorkspaceTabKind.diff);
    expect(controller.activeTab?.diff?.before, 'before\n');
    expect(controller.activeTab?.diff?.after, 'before\nafter\n');
  });

  test(
    'two distinct saved versions compare their own immutable blobs',
    () async {
      final file = File('${root.path}/README.md');
      await file.writeAsString('first\n');
      final resource = OpenMuseResource(
        uri: file.uri,
        displayName: 'README.md',
      );
      final controller = LocalWorkspaceController(
        rootPath: root.path,
        initialResources: [resource],
        versionStore: LocalVersionStore(
          Directory('${root.path}/.versions-test'),
        ),
      );
      final first = await controller.captureVersion(resource);
      await file.writeAsString('second\n');
      final second = await controller.captureVersion(resource);
      await file.writeAsString('working\n');
      await controller.openVersionComparison(
        resource,
        first,
        afterVersion: second,
      );
      expect(controller.activeTab?.diff?.before, 'first\n');
      expect(controller.activeTab?.diff?.after, 'second\n');
      expect(controller.activeTab?.diff?.afterLabel, second.shortId);
      await expectLater(
        controller.openVersionComparison(resource, first, afterVersion: first),
        throwsArgumentError,
      );
      await controller.openDiff(resource, first);
      expect(controller.activeTab?.diff?.after, 'working\n');
      expect(
        controller.tabs.where((tab) => tab.kind == WorkspaceTabKind.diff),
        hasLength(2),
      );
    },
  );
}
