import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

void main() {
  test('registry resolves editors and unloads plugin lifecycle', () async {
    final registry = OpenMusePluginRegistry(
      context: OpenMusePluginContext(executeHostCommand: (_, _) async => null),
    );
    final plugin = _TestPlugin();
    registry.install(plugin);
    final resource = OpenMuseResource(
      uri: Uri.file('/tmp/readme.md'),
      displayName: 'readme.md',
    );

    expect(registry.editorFor(resource), same(plugin));
    await registry.ensureActive(plugin);
    expect(plugin.activationCount, 1);
    await registry.ensureActive(plugin);
    expect(plugin.activationCount, 1);
    await registry.uninstall(plugin.descriptor.id);
    expect(plugin.deactivationCount, 1);
    expect(registry.editorFor(resource), isNull);
  });

  test('priority wins and catch-all handles an unknown extension', () {
    final registry = OpenMusePluginRegistry(
      context: OpenMusePluginContext(executeHostCommand: (_, _) async => null),
    );
    final text = _TestPlugin();
    final fallback = _FallbackPlugin();
    registry.install(fallback);
    registry.install(text);
    final markdown = OpenMuseResource(
      uri: Uri.file('/tmp/a.md'),
      displayName: 'a.md',
    );
    final unknown = OpenMuseResource(
      uri: Uri.file('/tmp/a.unknown'),
      displayName: 'a.unknown',
    );
    expect(registry.editorFor(markdown), same(text));
    expect(registry.editorFor(unknown), same(fallback));
    expect(registry.editorFor(markdown, editorId: 'fallback'), same(fallback));
  });
}

final class _FallbackPlugin implements OpenMusePlugin {
  @override
  final descriptor = const OpenMusePluginDescriptor(
    id: 'test.fallback',
    name: 'Fallback',
    version: '1.0.0',
    runtime: OpenMusePluginRuntime.builtIn,
    editors: [
      OpenMuseEditorContribution(
        id: 'fallback',
        extensions: {},
        priority: 0,
        catchAll: true,
      ),
    ],
  );
  @override
  Future<void> activate(OpenMusePluginContext context) async {}
  @override
  Future<void> deactivate() async {}
  @override
  Widget buildEditor(BuildContext context, OpenMuseResource resource) =>
      const SizedBox();
  @override
  Widget? buildPanel(BuildContext context, String panelId) => null;
}

final class _TestPlugin implements OpenMusePlugin {
  int activationCount = 0;
  int deactivationCount = 0;

  @override
  final descriptor = const OpenMusePluginDescriptor(
    id: 'test.editor',
    name: 'Test Editor',
    version: '1.0.0',
    runtime: OpenMusePluginRuntime.builtIn,
    editors: [
      OpenMuseEditorContribution(id: 'test', extensions: {'md'}, priority: 1),
    ],
  );

  @override
  Future<void> activate(OpenMusePluginContext context) async {
    activationCount++;
  }

  @override
  Future<void> deactivate() async {
    deactivationCount++;
  }

  @override
  Widget buildEditor(BuildContext context, OpenMuseResource resource) =>
      const SizedBox();

  @override
  Widget? buildPanel(BuildContext context, String panelId) => null;
}
