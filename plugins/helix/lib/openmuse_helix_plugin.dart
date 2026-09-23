library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:path/path.dart' as p;

import 'src/helix_editor_surface.dart';
import 'src/helix_language_servers.dart';
import 'src/helix_preferences.dart';
import 'src/helix_runtime.dart';

export 'src/helix_runtime.dart';
export 'src/helix_preferences.dart';
export 'src/helix_language_servers.dart';

final class OpenMuseHelixPlugin
    implements OpenMusePlugin, OpenMuseSettingsContributor {
  OpenMuseHelixPlugin({HelixRuntimePool? runtime}) : _runtime = runtime;

  HelixRuntimePool? _runtime;
  OpenMusePluginContext? _context;
  final ValueNotifier<HelixPreferences> _preferences = ValueNotifier(
    const HelixPreferences(),
  );

  @override
  final descriptor = const OpenMusePluginDescriptor(
    id: 'com.openmuse.helix',
    name: 'Helix Editor',
    version: '0.1.0',
    runtime: OpenMusePluginRuntime.nativeProcess,
    activationEvents: ['onFileType:text'],
    permissions: {
      'filesystem.workspace.read',
      'filesystem.workspace.write',
      'process.pty',
    },
    editors: [
      OpenMuseEditorContribution(
        id: 'helix.editor',
        extensions: {
          'txt',
          'md',
          'rs',
          'c',
          'cc',
          'cpp',
          'cs',
          'css',
          'diff',
          'go',
          'h',
          'hpp',
          'ini',
          'java',
          'jsx',
          'kt',
          'log',
          'lua',
          'mjs',
          'py',
          'rb',
          'scss',
          'sql',
          'swift',
          'tsx',
          'xml',
          'dart',
          'ts',
          'js',
          'json',
          'yaml',
          'yml',
          'toml',
          'sh',
          'bash',
          'zsh',
        },
        priority: 50,
      ),
    ],
  );

  @override
  Future<void> activate(OpenMusePluginContext context) async {
    _context = context;
    _runtime ??= HelixRuntimePool();
    final saved = await context.executeHostCommand(
      'settings.plugin.read',
      descriptor.id,
    );
    if (saved is Map) {
      _preferences.value = HelixPreferences.fromJson(saved);
    }
    await _runtime!.configure(_preferences.value);
  }

  @override
  Future<void> deactivate() async {
    await _runtime?.stop();
    _runtime?.dispose();
    _runtime = null;
    _context = null;
  }

  @override
  Widget buildEditor(BuildContext context, OpenMuseResource resource) {
    final runtime = _runtime;
    if (runtime == null) {
      throw StateError('Helix plugin must be active before building a surface');
    }
    return HelixEditorSurface(runtime: runtime, resource: resource);
  }

  @override
  Widget? buildPanel(BuildContext context, String panelId) => null;

  Future<void> updatePreferences(HelixPreferences next) async {
    _preferences.value = next;
    await _context?.executeHostCommand('settings.plugin.write', {
      'pluginId': descriptor.id,
      'values': next.toJson(),
    });
    await _runtime?.configure(next);
  }

  @override
  Widget buildSettings(
    BuildContext context,
  ) => ValueListenableBuilder<HelixPreferences>(
    valueListenable: _preferences,
    builder: (context, value, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Helix',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          '语法高亮来自 tree-sitter；Language Server 提供诊断、定义和引用。',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 13),
        _HelixSettingRow(
          label: '语法高亮',
          hint:
              '内置 ${HelixPreferences.bundledGrammarCount(_runtime?.executable ?? resolveHelixExecutable())} 个 tree-sitter grammars',
          trailing: TextButton(
            onPressed: () => _showGrammarStatus(context),
            child: const Text('查看状态'),
          ),
        ),
        _HelixSettingRow(
          label: '颜色主题',
          hint: '同时影响 Helix 运行时与终端画布',
          trailing: DropdownButton<String>(
            value: value.theme,
            items: const [
              DropdownMenuItem(
                value: 'onelight',
                child: Text('OpenMuse Light'),
              ),
              DropdownMenuItem(
                value: 'openmuse_dark',
                child: Text('OpenMuse Dark'),
              ),
            ],
            onChanged: (theme) {
              if (theme != null)
                updatePreferences(value.copyWith(theme: theme));
            },
          ),
        ),
        _HelixSettingRow(
          label: 'Keymap',
          hint: 'Helix 模态或常用 Ctrl+Z / Ctrl+Y 快捷键',
          trailing: DropdownButton<bool>(
            value: value.vscodeKeymap,
            items: const [
              DropdownMenuItem(value: false, child: Text('Helix（模态）')),
              DropdownMenuItem(value: true, child: Text('VS Code')),
            ],
            onChanged: (preset) {
              if (preset != null)
                updatePreferences(value.copyWith(vscodeKeymap: preset));
            },
          ),
        ),
        _HelixSettingRow(
          label: '字体',
          trailing: DropdownButton<String>(
            value: value.fontFamily,
            items: [
              for (final font in HelixPreferences.fonts)
                DropdownMenuItem(value: font, child: Text(font)),
            ],
            onChanged: (font) {
              if (font != null)
                updatePreferences(value.copyWith(fontFamily: font));
            },
          ),
        ),
        _HelixSettingRow(
          label: '字号 ${value.fontSize.round()}',
          trailing: SizedBox(
            width: 190,
            child: Slider(
              min: 11,
              max: 20,
              divisions: 9,
              value: value.fontSize,
              onChanged: (size) =>
                  updatePreferences(value.copyWith(fontSize: size)),
            ),
          ),
        ),
        _HelixSettingRow(
          label: 'Language Server',
          hint: '仅控制 LSP；不影响 tree-sitter 语法高亮',
          trailing: Switch.adaptive(
            value: value.enableLsp,
            onChanged: (enabled) =>
                updatePreferences(value.copyWith(enableLsp: enabled)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _configureLanguageServer(context, value),
                child: const Text('配置本地 Language Server…'),
              ),
              TextButton(
                onPressed: () => _showLanguageServerStatus(context, value),
                child: const Text('查看 LS 状态'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _showGrammarStatus(BuildContext context) {
    final count = HelixPreferences.bundledGrammarCount(
      _runtime?.executable ?? resolveHelixExecutable(),
    );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('tree-sitter 语法高亮'),
        content: Text(
          count > 0
              ? '当前内置 $count 个语法库。Helix 会按文件类型自动选择；Language Server 单独配置。'
              : '当前未检测到语法库。请使用包含 runtime/grammars 的发行包。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showLanguageServerStatus(
    BuildContext context,
    HelixPreferences preferences,
  ) {
    final statuses = inspectHelixLanguageServers(
      preferences.languageServerPaths,
    );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Language Server 状态'),
        content: SizedBox(
          width: 540,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final status in statuses)
                ListTile(
                  dense: true,
                  title: Text(status.spec.label),
                  subtitle: Text(status.path ?? '未找到；可在本机安装后指定可执行文件'),
                  trailing: Text(switch (status.presence) {
                    HelixServerPresence.custom => '自定义',
                    HelixServerPresence.system => '系统 PATH',
                    HelixServerPresence.missing => '未安装',
                  }),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _configureLanguageServer(
    BuildContext context,
    HelixPreferences current,
  ) async {
    var selected = helixLanguageServers.first.command;
    final pathController = TextEditingController(
      text: current.languageServerPaths[selected] ?? '',
    );
    String? error;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('配置本地 Language Server'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '选择语言服务，再指定本机已有的可执行文件。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButton<String>(
                    value: selected,
                    items: [
                      for (final server in helixLanguageServers)
                        DropdownMenuItem(
                          value: server.command,
                          child: Text(server.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selected = value;
                        error = null;
                        pathController.text =
                            current.languageServerPaths[value] ?? '';
                      });
                    },
                  ),
                  TextField(
                    controller: pathController,
                    decoration: InputDecoration(
                      labelText: '可执行文件的绝对路径',
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    '留空并保存可移除覆盖，改用系统 PATH 中的 Language Server。',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final path = pathController.text.trim();
                  if (path.isNotEmpty &&
                      (!p.isAbsolute(path) || !File(path).existsSync())) {
                    setDialogState(() => error = '请选择存在的绝对文件路径');
                    return;
                  }
                  final paths = Map<String, String>.of(
                    current.languageServerPaths,
                  );
                  if (path.isEmpty) {
                    paths.remove(selected);
                  } else {
                    paths[selected] = path;
                  }
                  await updatePreferences(
                    current.copyWith(languageServerPaths: paths),
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
    } finally {
      pathController.dispose();
    }
  }
}

final class _HelixSettingRow extends StatelessWidget {
  const _HelixSettingRow({
    required this.label,
    this.hint,
    required this.trailing,
  });
  final String label;
  final String? hint;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: hint == null ? 58 : 65,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              if (hint != null)
                Text(
                  hint!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );
}
