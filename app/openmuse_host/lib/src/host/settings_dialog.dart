import 'package:flutter/material.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

import 'design_system.dart';
import 'local_settings.dart';

Future<void> showOpenMuseSettings(
  BuildContext context,
  OpenMuseLocalSettings settings,
  OpenMusePluginRegistry registry,
) => showDialog<void>(
  context: context,
  barrierColor: OpenMuseTokens.scrim,
  builder: (_) => _SettingsDialog(settings: settings, registry: registry),
);

final class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.settings, required this.registry});

  final OpenMuseLocalSettings settings;
  final OpenMusePluginRegistry registry;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

final class _SettingsDialogState extends State<_SettingsDialog> {
  int selected = 0;

  static const sections = <(IconData, String)>[
    (Icons.dashboard_outlined, '工作区'),
    (Icons.extension_outlined, '插件'),
    (Icons.smart_toy_outlined, 'Agent'),
    (Icons.keyboard_outlined, '快捷键'),
    (Icons.info_outline, '关于'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: width < 950 ? width - 40 : 950,
        height: height < 590 ? height - 40 : 590,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              Container(
                width: 204,
                color: dark ? const Color(0xff202228) : const Color(0xfff8faff),
                padding: const EdgeInsets.fromLTRB(11, 25, 11, 12),
                child: Column(
                  children: [
                    for (var i = 0; i < sections.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Material(
                          color: selected == i
                              ? (dark
                                    ? const Color(0xff244154)
                                    : const Color(0xffd9f2ff))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () => setState(() => selected = i),
                            child: SizedBox(
                              height: 36,
                              child: Row(
                                children: [
                                  const SizedBox(width: 10),
                                  Icon(sections[i].$1, size: 18),
                                  const SizedBox(width: 12),
                                  Text(
                                    sections[i].$2,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ListenableBuilder(
                        listenable: widget.settings,
                        builder: (context, _) => switch (selected) {
                          0 => _WorkspaceSettings(settings: widget.settings),
                          1 => _PluginSettings(registry: widget.registry),
                          2 => _AgentSettings(
                            settings: widget.settings,
                            registry: widget.registry,
                          ),
                          3 => const _StaticSettings(
                            title: '快捷键',
                            description: '编辑器按键映射可在插件设置中调整。',
                          ),
                          _ => const _StaticSettings(
                            title: '关于 OpenMuse',
                            description: '本地优先的独立 Host + Plugin + DSH 产品。',
                          ),
                        },
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        tooltip: '关闭设置',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SettingsBody extends StatelessWidget {
  const _SettingsBody({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 3),
      Text(
        description,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 18),
      Divider(height: 1, color: Theme.of(context).dividerColor),
      const SizedBox(height: 23),
      ...children,
    ],
  );
}

final class _WorkspaceSettings extends StatelessWidget {
  const _WorkspaceSettings({required this.settings});
  final OpenMuseLocalSettings settings;

  @override
  Widget build(BuildContext context) => _SettingsBody(
    title: 'Workspace',
    description: '自定义本地工作区外观和面板布局。',
    children: [
      const Text(
        'Appearance',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 16,
        children: [
          for (final item in const [
            (ThemeMode.system, 'Auto', Icons.brightness_auto_outlined),
            (ThemeMode.light, 'Light', Icons.light_mode_outlined),
            (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
          ])
            _AppearanceCard(
              label: item.$2,
              icon: item.$3,
              selected: settings.themeMode == item.$1,
              onTap: () => settings.setThemeMode(item.$1),
            ),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        '布局',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 7),
      Text(
        '拖动工作区或 Agent 边缘可调节宽度，松开后自动保存。',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      _SettingRow(
        '工作区侧栏',
        '${settings.sidebarWidth?.round() ?? '自动'} px',
        onReset: () => settings.resetPaneWidth(sidebar: true),
      ),
      _SettingRow(
        'Agent 侧栏',
        '${settings.assistantWidth?.round() ?? '自动'} px',
        onReset: () => settings.resetPaneWidth(sidebar: false),
      ),
      const SizedBox(height: 24),
      Text(
        '文件只保存在已添加的本地 Project Workspace。',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

final class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(7),
    child: SizedBox(
      width: 88,
      child: Column(
        children: [
          Container(
            width: 88,
            height: 70,
            decoration: BoxDecoration(
              color: label == 'Dark'
                  ? const Color(0xff252a35)
                  : const Color(0xfffafbff),
              border: Border.all(
                color: selected
                    ? OpenMuseTokens.cyan
                    : Theme.of(context).dividerColor,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    icon,
                    color: label == 'Dark'
                        ? Colors.white70
                        : OpenMuseTokens.accent,
                  ),
                ),
                if (selected)
                  const Positioned(
                    top: 3,
                    left: 3,
                    child: Icon(
                      Icons.check_circle,
                      size: 15,
                      color: Color(0xff31b88a),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    ),
  );
}

final class _SettingRow extends StatelessWidget {
  const _SettingRow(this.label, this.value, {this.onReset});
  final String label;
  final String value;
  final VoidCallback? onReset;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 46,
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(value, style: const TextStyle(fontSize: 12)),
        if (onReset != null)
          IconButton(
            tooltip: '重置宽度',
            onPressed: onReset,
            icon: const Icon(Icons.history, size: 17),
          ),
      ],
    ),
  );
}

final class _PluginSettings extends StatelessWidget {
  const _PluginSettings({required this.registry});
  final OpenMusePluginRegistry registry;

  @override
  Widget build(BuildContext context) {
    final plugin = registry.plugin('com.openmuse.helix');
    final OpenMuseSettingsContributor? contributor =
        plugin is OpenMuseSettingsContributor
        ? plugin as OpenMuseSettingsContributor
        : null;
    return _SettingsBody(
      title: 'Plugin',
      description: '配置 Host 内嵌的编辑器插件；部分选项在下次打开文件时生效。',
      children: [
        if (contributor != null)
          FutureBuilder<void>(
            future: registry.activate(plugin!.descriptor.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Helix 设置加载失败：${snapshot.error}');
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              return contributor.buildSettings(context);
            },
          )
        else
          const Text('Helix 插件未安装。'),
        const SizedBox(height: 24),
        const Text(
          '已安装插件',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final descriptor in registry.descriptors)
          _SettingRow(descriptor.name, descriptor.version),
      ],
    );
  }
}

final class _AgentSettings extends StatelessWidget {
  const _AgentSettings({required this.settings, required this.registry});
  final OpenMuseLocalSettings settings;
  final OpenMusePluginRegistry registry;

  @override
  Widget build(BuildContext context) {
    final plugin = registry.plugin('com.openmuse.dsh-agent');
    final OpenMuseSettingsContributor? contributor =
        plugin is OpenMuseSettingsContributor
        ? plugin as OpenMuseSettingsContributor
        : null;
    return _SettingsBody(
      title: 'Agent',
      description: '配置本机 DSH 助手及右侧面板。',
      children: [
        const Text(
          '面板',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('显示 Agent', style: TextStyle(fontSize: 13)),
          subtitle: const Text('关闭后隐藏右侧面板，可随时重新打开。'),
          value: settings.assistantVisible,
          onChanged: settings.setAssistantVisible,
        ),
        if (contributor != null) contributor.buildSettings(context),
      ],
    );
  }
}

final class _StaticSettings extends StatelessWidget {
  const _StaticSettings({required this.title, required this.description});
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) =>
      _SettingsBody(title: title, description: description, children: const []);
}
