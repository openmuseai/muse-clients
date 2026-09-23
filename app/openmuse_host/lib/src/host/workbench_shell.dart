import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';

import 'design_system.dart';
import 'local_settings.dart';
import 'settings_dialog.dart';
import 'plugin_surface_host.dart';
import 'workspace_controller.dart';
import 'workspace_picker.dart';

final class OpenMuseWorkbench extends StatelessWidget {
  const OpenMuseWorkbench({
    super.key,
    required this.registry,
    required this.workspace,
    required this.settings,
  });

  final OpenMusePluginRegistry registry;
  final LocalWorkspaceController workspace;
  final OpenMuseLocalSettings settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([workspace, settings]),
    builder: (context, _) {
      final rightPlugin = registry.panelProvider(
        OpenMuseSurfaceRegion.rightSidebar,
        panelId: 'dsh.agent',
      );
      final windowWidth = MediaQuery.sizeOf(context).width;
      final hasRight = rightPlugin != null && settings.assistantVisible;
      final sidebarWidth = workspace.sidebarVisible
          ? (settings.sidebarWidth ??
                    OpenMuseTokens.sidebarWidthFor(windowWidth))
                .clamp(
                  180.0,
                  math.max(180.0, windowWidth - (hasRight ? 560 : 280)),
                )
                .toDouble()
          : 0.0;
      final assistantWidth = hasRight
          ? (settings.assistantWidth ??
                    OpenMuseTokens.assistantWidthFor(windowWidth))
                .clamp(280.0, math.max(280.0, windowWidth - sidebarWidth - 280))
                .toDouble()
          : 0.0;
      return Scaffold(
        body: Row(
          children: [
            if (workspace.sidebarVisible) ...[
              SizedBox(
                width: sidebarWidth,
                child: _WorkspaceSidebar(
                  registry: registry,
                  workspace: workspace,
                  settings: settings,
                ),
              ),
              _PaneResizer(
                onDelta: (delta) => settings.setPaneWidth(
                  sidebar: (settings.sidebarWidth ?? sidebarWidth) + delta,
                ),
                onEnd: settings.save,
              ),
            ],
            Expanded(
              child: _EditorArea(
                registry: registry,
                workspace: workspace,
                settings: settings,
              ),
            ),
            if (hasRight) ...[
              _PaneResizer(
                onDelta: (delta) => settings.setPaneWidth(
                  assistant:
                      (settings.assistantWidth ?? assistantWidth) - delta,
                ),
                onEnd: settings.save,
              ),
              SizedBox(
                width: assistantWidth,
                child: PluginPanelHost(
                  registry: registry,
                  plugin: rightPlugin,
                  panelId: 'dsh.agent',
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Tracks pointer movement globally so dragging remains reliable over the
/// embedded DSH WebView, whose native surface can swallow local mouse-up.
final class _PaneResizer extends StatefulWidget {
  const _PaneResizer({required this.onDelta, required this.onEnd});

  final ValueChanged<double> onDelta;
  final Future<void> Function() onEnd;

  @override
  State<_PaneResizer> createState() => _PaneResizerState();
}

final class _PaneResizerState extends State<_PaneResizer> {
  int? _pointer;
  double _lastX = 0;
  bool _hovered = false;
  bool _dragging = false;

  void _onGlobalPointer(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      final delta = event.position.dx - _lastX;
      _lastX = event.position.dx;
      widget.onDelta(delta);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _finish();
    }
  }

  void _finish() {
    if (_pointer == null) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    _pointer = null;
    if (mounted) setState(() => _dragging = false);
    widget.onEnd();
  }

  @override
  void dispose() {
    if (_pointer != null) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeLeftRight,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (event.buttons != kPrimaryButton) return;
        _finish();
        _pointer = event.pointer;
        _lastX = event.position.dx;
        setState(() => _dragging = true);
        GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
      },
      child: Container(
        key: const Key('pane-resizer'),
        width: 6,
        color: _hovered || _dragging
            ? OpenMuseTokens.cyan.withValues(alpha: 0.65)
            : Theme.of(context).dividerColor.withValues(alpha: 0.5),
      ),
    ),
  );
}

final class _WorkspaceSidebar extends StatelessWidget {
  const _WorkspaceSidebar({
    required this.registry,
    required this.workspace,
    required this.settings,
  });

  final OpenMusePluginRegistry registry;
  final LocalWorkspaceController workspace;
  final OpenMuseLocalSettings settings;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).brightness == Brightness.light
        ? OpenMuseTokens.sidebar
        : const Color(0xff202228),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xffe8ebff),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.auto_awesome,
                      color: OpenMuseTokens.accent,
                      size: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'OpenMuse',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                _SmallIconButton(
                  tooltip: '本地设置',
                  icon: Icons.settings_outlined,
                  onPressed: () =>
                      showOpenMuseSettings(context, settings, registry),
                ),
                _SmallIconButton(
                  tooltip: '收起侧栏',
                  icon: Icons.view_sidebar_outlined,
                  onPressed: workspace.toggleSidebar,
                ),
              ],
            ),
            const SizedBox(height: 11),
            _SidebarAction(
              icon: Icons.search,
              label: '搜索',
              shortcut: '⌘ K',
              onTap: () => _showSearch(context, workspace),
            ),
            _SidebarAction(
              icon: Icons.add_circle,
              label: '新建文档',
              accent: true,
              onTap: () => _createDocument(context, workspace),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('project-workspace-toggle'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: workspace.toggleProjectSection,
                      child: SizedBox(
                        height: 30,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Project Workspace',
                                overflow: TextOverflow.ellipsis,
                                style: OpenMuseTokens.compactText.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              workspace.projectSectionExpanded
                                  ? Icons.keyboard_arrow_down
                                  : Icons.chevron_right,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _SmallIconButton(
                    tooltip: '添加工作区',
                    icon: Icons.add,
                    onPressed: () => _addWorkspace(context, workspace),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Expanded(
              child: ListView(
                children: [
                  if (workspace.projectSectionExpanded)
                    for (final mount in workspace.mounts) ...[
                      _MountRow(
                        mount: mount,
                        registry: registry,
                        workspace: workspace,
                        settings: settings,
                      ),
                      for (final entry in workspace.visibleEntries(mount))
                        _ResourceRow(
                          entry: entry,
                          registry: registry,
                          workspace: workspace,
                          settings: settings,
                          selected:
                              entry.path ==
                              workspace.selected?.uri.toFilePath(),
                        ),
                    ],
                ],
              ),
            ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: _FooterAction(
                    icon: Icons.extension_outlined,
                    label: '插件',
                    onTap: () => _showPlugins(context, registry),
                  ),
                ),
                const SizedBox(width: 6),
                const _FooterAction(icon: Icons.delete_outline, label: '回收站'),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

final class _SidebarAction extends StatelessWidget {
  const _SidebarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final bool accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: SizedBox(
        height: OpenMuseTokens.itemHeight,
        child: Row(
          children: [
            const SizedBox(width: 4),
            Icon(
              icon,
              size: 17,
              color: accent ? OpenMuseTokens.cyan : OpenMuseTokens.textMuted,
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: OpenMuseTokens.compactText.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (shortcut != null) ...[
              const Spacer(),
              Text(
                shortcut!,
                style: const TextStyle(
                  color: OpenMuseTokens.textMuted,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    ),
  );
}

final class _MountRow extends StatelessWidget {
  const _MountRow({
    required this.mount,
    required this.registry,
    required this.workspace,
    required this.settings,
  });

  final WorkspaceMount mount;
  final OpenMusePluginRegistry registry;
  final LocalWorkspaceController workspace;
  final OpenMuseLocalSettings settings;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => workspace.toggleDirectory(mount.root),
      onSecondaryTapDown: (details) => _showResourceMenu(
        context,
        details.globalPosition,
        mount.root,
        registry,
        workspace,
        settings,
      ),
      child: SizedBox(
        height: OpenMuseTokens.itemHeight,
        child: Row(
          children: [
            Icon(
              mount.root.expanded
                  ? Icons.keyboard_arrow_down
                  : Icons.chevron_right,
              size: 15,
            ),
            Icon(
              mount.root.expanded
                  ? Icons.folder_open_outlined
                  : Icons.folder_outlined,
              size: 16,
              color: OpenMuseTokens.cyan,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                mount.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (mount.root.loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    ),
  );
}

final class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.entry,
    required this.registry,
    required this.workspace,
    required this.settings,
    required this.selected,
  });

  final WorkspaceEntry entry;
  final OpenMusePluginRegistry registry;
  final LocalWorkspaceController workspace;
  final OpenMuseLocalSettings settings;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 1),
    child: Material(
      color: selected
          ? (Theme.of(context).brightness == Brightness.dark
                ? const Color(0xff383c47)
                : OpenMuseTokens.sidebarSelected)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => entry.isDirectory
            ? workspace.toggleDirectory(entry)
            : workspace.openResource(entry.resource),
        onSecondaryTapDown: (details) => _showResourceMenu(
          context,
          details.globalPosition,
          entry,
          registry,
          workspace,
          settings,
        ),
        child: SizedBox(
          height: 30,
          child: Row(
            children: [
              SizedBox(width: 4 + entry.depth * 12),
              if (entry.isDirectory)
                Icon(
                  entry.expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.chevron_right,
                  size: 15,
                  color: OpenMuseTokens.textMuted,
                )
              else
                const SizedBox(width: 15),
              Icon(
                entry.isDirectory
                    ? (entry.expanded
                          ? Icons.folder_open_outlined
                          : Icons.folder_outlined)
                    : _iconFor(entry.resource.extension),
                size: 16,
                color: entry.isDirectory
                    ? OpenMuseTokens.cyan
                    : OpenMuseTokens.textMuted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  entry.name,
                  overflow: TextOverflow.ellipsis,
                  style: OpenMuseTokens.compactText.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    ),
  );

  static IconData iconFor(String extension) => switch (extension) {
    'png' || 'jpg' || 'jpeg' => Icons.image_outlined,
    'pdf' => Icons.picture_as_pdf_outlined,
    'native-gate' => Icons.developer_board_outlined,
    'md' => Icons.notes_outlined,
    _ => Icons.insert_drive_file_outlined,
  };

  IconData _iconFor(String extension) => iconFor(extension);
}

Future<void> _addWorkspace(
  BuildContext context,
  LocalWorkspaceController workspace,
) async {
  String? path;
  try {
    path = await const WorkspacePicker().chooseDirectory();
  } on MissingPluginException {
    if (!context.mounted) return;
    path = await _promptText(context, '添加工作区', '本地目录路径');
  }
  if (path == null || path.trim().isEmpty || !context.mounted) return;
  try {
    await workspace.addWorkspace(path);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('无法添加工作区：$error')));
  }
}

PopupMenuItem<String> _menuAction(
  String value,
  String label,
  IconData icon, {
  bool destructive = false,
  bool enabled = true,
  Widget? trailing,
}) => PopupMenuItem<String>(
  value: value,
  enabled: enabled,
  height: 34,
  padding: const EdgeInsets.symmetric(horizontal: 10),
  child: Row(
    children: [
      Icon(
        icon,
        size: 16,
        color: destructive ? const Color(0xffe40046) : OpenMuseTokens.textMuted,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: destructive ? const Color(0xffe40046) : null,
          ),
        ),
      ),
      ?trailing,
    ],
  ),
);

Future<String?> _showWorkbenchMenu(
  BuildContext context,
  Offset position, {
  required List<PopupMenuEntry<String>> items,
}) => showMenu<String>(
  context: context,
  position: RelativeRect.fromLTRB(
    position.dx,
    position.dy,
    position.dx,
    position.dy,
  ),
  items: items,
  constraints: const BoxConstraints(
    minWidth: 260,
    maxWidth: 280,
    maxHeight: 480,
  ),
  menuPadding: const EdgeInsets.all(6),
  color: Theme.of(context).dialogTheme.backgroundColor,
  surfaceTintColor: Colors.transparent,
  elevation: 12,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
    side: BorderSide(color: Theme.of(context).dividerColor),
  ),
);

/// The menu is driven solely by editor contributions, never by a Host format
/// switch. A plugin can be installed/uninstalled without changing this menu.
Future<void> _showOpenWithMenu(
  BuildContext context,
  Offset origin,
  OpenMuseResource resource,
  OpenMusePluginRegistry registry,
  LocalWorkspaceController workspace,
  OpenMuseLocalSettings settings, {
  bool defaultsOnly = false,
}) async {
  final unique = <String, OpenMuseEditorCandidate>{};
  for (final candidate in registry.editorCandidates(resource)) {
    unique.putIfAbsent(candidate.plugin.descriptor.id, () => candidate);
  }
  final selected = defaultsOnly
      ? settings.defaultEditorFor(resource.extension)
      : workspace.tabs
                .where(
                  (tab) =>
                      tab.kind == WorkspaceTabKind.resource &&
                      tab.resource.uri == resource.uri,
                )
                .firstOrNull
                ?.preferredEditorId ??
            settings.defaultEditorFor(resource.extension) ??
            registry.editorCandidates(resource).firstOrNull?.editor.id;
  final candidates = unique.values.toList();
  final command = await _showWorkbenchMenu(
    context,
    origin,
    items: [
      if (!candidates.any(
        (candidate) =>
            candidate.plugin.descriptor.name.toLowerCase().contains('ioffice'),
      ))
        _menuAction(
          'ioffice',
          'iOffice',
          Icons.description_outlined,
          enabled: false,
        ),
      for (final candidate in candidates)
        _menuAction(
          'editor:${candidate.editor.id}',
          candidate.plugin.descriptor.name == 'Helix Editor'
              ? 'Helix'
              : candidate.plugin.descriptor.name,
          candidate.plugin.descriptor.id == 'com.openmuse.helix'
              ? Icons.code
              : Icons.visibility_outlined,
          trailing: selected == candidate.editor.id
              ? const Icon(Icons.check, size: 16)
              : null,
        ),
      if (!defaultsOnly) ...[
        const PopupMenuDivider(height: 12),
        _menuAction(
          'defaults',
          '默认打开方式',
          Icons.star_outline,
          trailing: const Icon(Icons.chevron_right, size: 16),
        ),
      ],
    ],
  );
  if (command == null || !context.mounted) return;
  if (command == 'defaults') {
    await _showOpenWithMenu(
      context,
      Offset(origin.dx + 270, origin.dy + candidates.length * 34 + 46),
      resource,
      registry,
      workspace,
      settings,
      defaultsOnly: true,
    );
  } else if (command.startsWith('editor:')) {
    final editorId = command.substring('editor:'.length);
    if (defaultsOnly) {
      await settings.setDefaultEditor(resource.extension, editorId);
    }
    workspace.openResource(resource, editorId: editorId);
  }
}

Future<void> _showVersionMenu(
  BuildContext context,
  Offset origin,
  OpenMuseResource resource,
  LocalWorkspaceController workspace,
) async {
  final versions = await workspace.versions(resource);
  if (!context.mounted) return;
  final command = await _showWorkbenchMenu(
    context,
    origin,
    items: [
      _menuAction(
        'current',
        '当前工作副本',
        Icons.history,
        trailing: const Icon(Icons.check_circle_outline, size: 15),
      ),
      const PopupMenuDivider(height: 12),
      if (versions.isEmpty)
        _menuAction('empty', '尚未保存版本', Icons.info_outline, enabled: false),
      for (var index = 0; index < versions.length; index++)
        _menuAction(
          'version:$index',
          '${versions[index].shortId} · ${versions[index].createdAt.toLocal().hour.toString().padLeft(2, '0')}:${versions[index].createdAt.toLocal().minute.toString().padLeft(2, '0')}',
          Icons.radio_button_unchecked,
        ),
    ],
  );
  if (command == null || !command.startsWith('version:')) return;
  final index = int.tryParse(command.substring('version:'.length));
  if (index == null || index < 0 || index >= versions.length) return;
  await workspace.openDiff(resource, versions[index]);
}

Future<void> _showResourceMenu(
  BuildContext context,
  Offset position,
  WorkspaceEntry entry,
  OpenMusePluginRegistry registry,
  LocalWorkspaceController workspace,
  OpenMuseLocalSettings settings,
) async {
  final resource = entry.resource;
  final isMountRoot = workspace.mounts.any((m) => identical(m.root, entry));
  final command = await _showWorkbenchMenu(
    context,
    position,
    items: [
      _menuAction(
        'open',
        entry.isDirectory ? '展开／收起' : 'Open',
        Icons.open_in_new,
      ),
      if (entry.isDirectory) ...[
        const PopupMenuDivider(height: 12),
        _menuAction('new-file', 'New File…', Icons.note_add_outlined),
        _menuAction(
          'new-folder',
          'New Folder…',
          Icons.create_new_folder_outlined,
        ),
        _menuAction('refresh', 'Refresh', Icons.refresh),
      ],
      if (!entry.isDirectory)
        _menuAction(
          'open-with',
          '打开方式',
          Icons.open_in_new,
          trailing: const Icon(Icons.chevron_right, size: 16),
        ),
      if (!entry.isDirectory) ...[
        const PopupMenuDivider(height: 12),
        _menuAction('capture', '保存当前版本', Icons.save_outlined),
        _menuAction(
          'version',
          '版本',
          Icons.history,
          trailing: const Icon(Icons.chevron_right, size: 16),
        ),
        _menuAction('history', '版本历史与审计…', Icons.history),
      ],
      const PopupMenuDivider(height: 12),
      _menuAction('copy', 'Copy Path', Icons.content_copy_outlined),
      _menuAction(
        'copy-relative',
        'Copy Relative Path',
        Icons.copy_all_outlined,
      ),
      if (!isMountRoot)
        _menuAction('rename', 'Rename…', Icons.drive_file_rename_outline),
      _menuAction('reveal', 'Reveal in Finder', Icons.folder_open_outlined),
      const PopupMenuDivider(height: 12),
      if (isMountRoot && workspace.mounts.length > 1)
        _menuAction(
          'unmount',
          'Remove Workspace',
          Icons.remove_circle_outline,
          destructive: true,
        ),
      if (!isMountRoot)
        _menuAction(
          'delete',
          'Delete',
          Icons.delete_outline,
          destructive: true,
        ),
    ],
  );
  if (command == null || !context.mounted) return;
  if (command == 'open') {
    entry.isDirectory
        ? await workspace.toggleDirectory(entry)
        : workspace.openResource(resource);
  } else if (command == 'open-with') {
    await _showOpenWithMenu(
      context,
      Offset(position.dx + 270, position.dy + 34),
      resource,
      registry,
      workspace,
      settings,
    );
  } else if (command == 'capture') {
    final snapshot = await workspace.captureVersion(resource);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存版本 ${snapshot.shortId}')));
    }
  } else if (command == 'history') {
    await _showVersionHistory(context, resource, workspace);
  } else if (command == 'version') {
    await _showVersionMenu(
      context,
      Offset(position.dx + 270, position.dy + 128),
      resource,
      workspace,
    );
  } else if (command == 'new-file' || command == 'new-folder') {
    final directory = command == 'new-folder';
    final name = await _promptText(
      context,
      directory ? '新建文件夹' : '新建文件',
      directory ? '文件夹名称' : '文件名',
    );
    if (name != null) {
      try {
        final created = await workspace.createEntry(
          entry,
          name,
          directory: directory,
        );
        if (!directory) workspace.openResource(created.resource);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('无法创建：$error')));
        }
      }
    }
  } else if (command == 'refresh') {
    await workspace.refreshDirectory(entry);
  } else if (command == 'copy') {
    await Clipboard.setData(ClipboardData(text: entry.path));
  } else if (command == 'copy-relative') {
    await Clipboard.setData(
      ClipboardData(text: workspace.relativePath(resource)),
    );
  } else if (command == 'rename') {
    final name = await _promptText(
      context,
      '重命名',
      entry.name,
      initialValue: entry.name,
    );
    if (name != null) await workspace.renameEntry(entry, name);
  } else if (command == 'reveal') {
    await const WorkspacePicker().reveal(entry.path);
  } else if (command == 'delete') {
    final confirmed = await _confirmDelete(context, entry.name);
    if (confirmed) await workspace.deleteEntry(entry);
  } else if (command == 'unmount') {
    final mount = workspace.mounts.firstWhere((m) => identical(m.root, entry));
    await workspace.removeWorkspace(mount);
  }
}

Future<void> _showTabMenu(
  BuildContext context,
  Offset position,
  WorkspaceTab tab,
  OpenMusePluginRegistry registry,
  LocalWorkspaceController workspace,
  OpenMuseLocalSettings settings,
) async {
  final command = await _showWorkbenchMenu(
    context,
    position,
    items: [
      _menuAction('close', 'Close', Icons.close),
      _menuAction('close-others', 'Close other tabs', Icons.tab_unselected),
      if (tab.kind == WorkspaceTabKind.resource) ...[
        const PopupMenuDivider(height: 12),
        _menuAction(
          'open-with',
          '打开方式',
          Icons.open_in_new,
          trailing: const Icon(Icons.chevron_right, size: 16),
        ),
        _menuAction('capture', '保存当前版本', Icons.save_outlined),
        _menuAction(
          'version',
          '版本',
          Icons.history,
          trailing: const Icon(Icons.chevron_right, size: 16),
        ),
        _menuAction('history', '版本历史与审计…', Icons.history),
        const PopupMenuDivider(height: 12),
        _menuAction('copy', 'Copy Path', Icons.content_copy_outlined),
        _menuAction(
          'copy-relative',
          'Copy Relative Path',
          Icons.copy_all_outlined,
        ),
        _menuAction('reveal', '在 Finder 中显示', Icons.folder_open_outlined),
      ],
      _menuAction('pin', tab.pinned ? 'Unpin' : 'Pin', Icons.push_pin_outlined),
    ],
  );
  if (command == null || !context.mounted) return;
  if (command == 'close') {
    workspace.closeTab(tab);
  } else if (command == 'close-others') {
    workspace.closeOtherTabs(tab);
  } else if (command == 'pin') {
    workspace.togglePinned(tab);
  } else if (command == 'open-with') {
    await _showOpenWithMenu(
      context,
      Offset(position.dx + 270, position.dy + 80),
      tab.resource,
      registry,
      workspace,
      settings,
    );
  } else if (command == 'capture') {
    final snapshot = await workspace.captureVersion(tab.resource);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存版本 ${snapshot.shortId}')));
    }
  } else if (command == 'history') {
    await _showVersionHistory(context, tab.resource, workspace);
  } else if (command == 'version') {
    await _showVersionMenu(
      context,
      Offset(position.dx + 270, position.dy + 148),
      tab.resource,
      workspace,
    );
  } else if (command == 'copy') {
    await Clipboard.setData(ClipboardData(text: tab.resource.uri.toFilePath()));
  } else if (command == 'copy-relative') {
    await Clipboard.setData(
      ClipboardData(text: workspace.relativePath(tab.resource)),
    );
  } else if (command == 'reveal') {
    await const WorkspacePicker().reveal(tab.resource.uri.toFilePath());
  }
}

Future<void> _showVersionHistory(
  BuildContext context,
  OpenMuseResource resource,
  LocalWorkspaceController workspace,
) async {
  final versions = await workspace.versions(resource);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${resource.displayName} · 版本历史与审计'),
      content: SizedBox(
        width: 620,
        height: 380,
        child: versions.isEmpty
            ? const Center(child: Text('尚未保存本地版本'))
            : ListView.separated(
                itemCount: versions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final version = versions[index];
                  return ListTile(
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(version.shortId),
                    subtitle: Text(
                      '${version.createdAt.toLocal()}  ·  ${version.byteLength} bytes',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await workspace.openDiff(resource, version);
                          },
                          child: const Text('与当前比较'),
                        ),
                        PopupMenuButton<LocalVersionSnapshot>(
                          tooltip: '选择另一个历史版本',
                          onSelected: (other) async {
                            Navigator.pop(context);
                            await workspace.openVersionComparison(
                              resource,
                              version,
                              afterVersion: other,
                            );
                          },
                          itemBuilder: (_) => [
                            for (final other in versions)
                              if (other.id != version.id)
                                PopupMenuItem(
                                  value: other,
                                  child: Text('与 ${other.shortId} 比较'),
                                ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('与版本比较 ▸'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
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

Future<String?> _promptText(
  BuildContext context,
  String title,
  String label, {
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<bool> _confirmDelete(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地资源？'),
        content: Text('“$name”将从磁盘永久删除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffd9304f),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ) ??
    false;

final class _EditorArea extends StatelessWidget {
  const _EditorArea({
    required this.registry,
    required this.workspace,
    required this.settings,
  });

  final OpenMusePluginRegistry registry;
  final LocalWorkspaceController workspace;
  final OpenMuseLocalSettings settings;

  @override
  Widget build(BuildContext context) {
    final tab = workspace.activeTab;
    final current = tab?.resource;
    final plugin = current == null || tab?.kind == WorkspaceTabKind.diff
        ? null
        : registry.editorFor(
            current,
            editorId:
                tab?.preferredEditorId ??
                settings.defaultEditorFor(current.extension),
          );
    return Column(
      children: [
        _TabStrip(registry: registry, workspace: workspace, settings: settings),
        if (tab?.kind != WorkspaceTabKind.diff && current != null)
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xff202329),
            alignment: Alignment.centerLeft,
            child: const Text(
              '右键标签或文件打开菜单 · Ctrl+S 保存 · Esc 进入 Helix 命令模式',
              style: TextStyle(color: Color(0xffc9cbd1), fontSize: 11),
            ),
          ),
        Expanded(
          child: tab == null
              ? _Welcome(
                  onSearch: () => _showSearch(context, workspace),
                  onCreate: () => _createDocument(context, workspace),
                )
              : tab.kind == WorkspaceTabKind.diff
              ? _DiffWorkbench(diff: tab.diff!)
              : plugin == null
              ? const Center(child: Text('没有已安装的插件可以打开这个资源。'))
              : PluginEditorHost(
                  key: ValueKey('${plugin.descriptor.id}:${tab.resource.uri}'),
                  registry: registry,
                  plugin: plugin,
                  resource: tab.resource,
                ),
        ),
      ],
    );
  }
}

final class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.registry,
    required this.workspace,
    required this.settings,
  });

  final OpenMusePluginRegistry registry;
  final LocalWorkspaceController workspace;
  final OpenMuseLocalSettings settings;

  @override
  Widget build(BuildContext context) => Container(
    height: OpenMuseTokens.topBarHeight,
    decoration: BoxDecoration(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xff202228)
          : const Color(0xfff7f8fb),
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        if (!workspace.sidebarVisible)
          _SmallIconButton(
            tooltip: '展开侧栏',
            icon: Icons.view_sidebar_outlined,
            onPressed: workspace.toggleSidebar,
          ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              if (workspace.tabs.isEmpty)
                SizedBox(
                  width: 112,
                  child: Center(
                    child: Text(
                      'Blank page',
                      style: OpenMuseTokens.compactText.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              for (final tab in workspace.tabs)
                _WorkbenchTab(
                  tab: tab,
                  workspace: workspace,
                  registry: registry,
                  settings: settings,
                ),
            ],
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );
}

final class _WorkbenchTab extends StatefulWidget {
  const _WorkbenchTab({
    required this.tab,
    required this.workspace,
    required this.registry,
    required this.settings,
  });

  final WorkspaceTab tab;
  final LocalWorkspaceController workspace;
  final OpenMusePluginRegistry registry;
  final OpenMuseLocalSettings settings;

  @override
  State<_WorkbenchTab> createState() => _WorkbenchTabState();
}

final class _WorkbenchTabState extends State<_WorkbenchTab> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = identical(widget.tab, widget.workspace.activeTab);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (details) => _showTabMenu(
          context,
          details.globalPosition,
          widget.tab,
          widget.registry,
          widget.workspace,
          widget.settings,
        ),
        child: Material(
          color: Theme.of(context).brightness == Brightness.dark
              ? (active ? const Color(0xff292c34) : const Color(0xff202228))
              : (active ? Colors.white : const Color(0xfff7f8fb)),
          child: InkWell(
            onTap: () => widget.workspace.activateTab(widget.tab),
            child: Container(
              constraints: BoxConstraints(
                minWidth: widget.tab.pinned ? 54 : (active ? 128 : 88),
                maxWidth: widget.tab.pinned ? 54 : 168,
              ),
              padding: EdgeInsets.only(left: active ? 14 : 10, right: 4),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.tab.kind == WorkspaceTabKind.diff
                        ? Icons.difference_outlined
                        : _ResourceRow.iconFor(widget.tab.resource.extension),
                    size: 15,
                    color: OpenMuseTokens.textMuted,
                  ),
                  if (!widget.tab.pinned) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.tab.title,
                        overflow: TextOverflow.ellipsis,
                        style: OpenMuseTokens.compactText.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                  if (!widget.tab.pinned && (active || hovered))
                    IconButton(
                      tooltip: '关闭',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 24,
                        height: 24,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => widget.workspace.closeTab(widget.tab),
                      icon: const Icon(Icons.close, size: 14),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _DiffRowKind { equal, added, deleted }

final class _DiffRow {
  const _DiffRow(this.kind, this.oldLine, this.newLine, this.text);
  final _DiffRowKind kind;
  final int? oldLine;
  final int? newLine;
  final String text;
}

final class _DiffWorkbench extends StatefulWidget {
  const _DiffWorkbench({required this.diff});
  final WorkspaceDiff diff;

  @override
  State<_DiffWorkbench> createState() => _DiffWorkbenchState();
}

final class _DiffWorkbenchState extends State<_DiffWorkbench> {
  late final List<_DiffRow> rows = _lineDiff(
    widget.diff.before,
    widget.diff.after,
  );
  bool sideBySide = false;

  int get additions =>
      rows.where((row) => row.kind == _DiffRowKind.added).length;
  int get deletions =>
      rows.where((row) => row.kind == _DiffRowKind.deleted).length;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff202228)
              : const Color(0xfff7f8fb),
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            _DiffPill(
              '$additions 处变更',
              const Color(0xffe5f4ff),
              const Color(0xff1581bd),
            ),
            const SizedBox(width: 6),
            _DiffPill(
              '+$additions',
              const Color(0xffe8f8e9),
              const Color(0xff2e9b45),
            ),
            const SizedBox(width: 6),
            _DiffPill(
              '-$deletions',
              const Color(0xffffeeee),
              const Color(0xffd74b4b),
            ),
            const SizedBox(width: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('统一')),
                ButtonSegment(value: true, label: Text('并排')),
              ],
              selected: {sideBySide},
              onSelectionChanged: (value) =>
                  setState(() => sideBySide = value.single),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const Spacer(),
            Text(
              '快照 ${widget.diff.snapshot.shortId}  ↔  ${widget.diff.afterLabel}',
              style: const TextStyle(
                fontSize: 11,
                color: OpenMuseTokens.textMuted,
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: sideBySide
            ? _SideBySideDiff(rows: rows)
            : _UnifiedDiff(rows: rows),
      ),
    ],
  );
}

final class _DiffPill extends StatelessWidget {
  const _DiffPill(this.label, this.background, this.foreground);
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(label, style: TextStyle(fontSize: 11, color: foreground)),
  );
}

final class _UnifiedDiff extends StatelessWidget {
  const _UnifiedDiff({required this.rows});
  final List<_DiffRow> rows;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: rows.length,
    itemExtent: 22,
    itemBuilder: (context, index) {
      final row = rows[index];
      final dark = Theme.of(context).brightness == Brightness.dark;
      final colors = switch (row.kind) {
        _DiffRowKind.added => (
          dark ? const Color(0xff20382a) : const Color(0xffe8f6e9),
          dark ? const Color(0xff85d79b) : const Color(0xff35a853),
          '+',
        ),
        _DiffRowKind.deleted => (
          dark ? const Color(0xff42282a) : const Color(0xffffecec),
          dark ? const Color(0xffff9292) : const Color(0xffd94b4b),
          '-',
        ),
        _DiffRowKind.equal => (
          Theme.of(context).scaffoldBackgroundColor,
          OpenMuseTokens.textMuted,
          ' ',
        ),
      };
      return ColoredBox(
        color: colors.$1,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                '${row.oldLine ?? ''}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10,
                  color: OpenMuseTokens.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              child: Text(
                '${row.newLine ?? ''}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10,
                  color: OpenMuseTokens.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              colors.$3,
              style: TextStyle(color: colors.$2, fontFamily: 'Menlo'),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                row.text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
              ),
            ),
          ],
        ),
      );
    },
  );
}

final class _SideBySideDiff extends StatelessWidget {
  const _SideBySideDiff({required this.rows});
  final List<_DiffRow> rows;

  @override
  Widget build(BuildContext context) => ListView.builder(
    itemCount: rows.length,
    itemExtent: 24,
    itemBuilder: (context, index) {
      final row = rows[index];
      return Row(
        children: [
          Expanded(
            child: _DiffCell(
              line: row.oldLine,
              text: row.kind == _DiffRowKind.added ? '' : row.text,
              deleted: row.kind == _DiffRowKind.deleted,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _DiffCell(
              line: row.newLine,
              text: row.kind == _DiffRowKind.deleted ? '' : row.text,
              added: row.kind == _DiffRowKind.added,
            ),
          ),
        ],
      );
    },
  );
}

final class _DiffCell extends StatelessWidget {
  const _DiffCell({
    this.line,
    required this.text,
    this.added = false,
    this.deleted = false,
  });
  final int? line;
  final String text;
  final bool added;
  final bool deleted;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: added
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff20382a)
              : const Color(0xffe8f6e9))
        : deleted
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xff42282a)
              : const Color(0xffffecec))
        : Theme.of(context).scaffoldBackgroundColor,
    child: Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            '${line ?? ''}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 10,
              color: OpenMuseTokens.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

List<_DiffRow> _lineDiff(String before, String after) {
  final oldLines = before.replaceAll('\r\n', '\n').split('\n');
  final newLines = after.replaceAll('\r\n', '\n').split('\n');
  if (oldLines.length * newLines.length > 4000000) {
    return [
      for (var i = 0; i < oldLines.length; i++)
        _DiffRow(_DiffRowKind.deleted, i + 1, null, oldLines[i]),
      for (var i = 0; i < newLines.length; i++)
        _DiffRow(_DiffRowKind.added, null, i + 1, newLines[i]),
    ];
  }
  final matrix = List.generate(
    oldLines.length + 1,
    (_) => List<int>.filled(newLines.length + 1, 0),
  );
  for (var i = oldLines.length - 1; i >= 0; i--) {
    for (var j = newLines.length - 1; j >= 0; j--) {
      matrix[i][j] = oldLines[i] == newLines[j]
          ? matrix[i + 1][j + 1] + 1
          : (matrix[i + 1][j] >= matrix[i][j + 1]
                ? matrix[i + 1][j]
                : matrix[i][j + 1]);
    }
  }
  final rows = <_DiffRow>[];
  var i = 0;
  var j = 0;
  while (i < oldLines.length || j < newLines.length) {
    if (i < oldLines.length &&
        j < newLines.length &&
        oldLines[i] == newLines[j]) {
      rows.add(_DiffRow(_DiffRowKind.equal, i + 1, j + 1, oldLines[i]));
      i++;
      j++;
    } else if (j < newLines.length &&
        (i == oldLines.length || matrix[i][j + 1] >= matrix[i + 1][j])) {
      rows.add(_DiffRow(_DiffRowKind.added, null, j + 1, newLines[j++]));
    } else {
      rows.add(_DiffRow(_DiffRowKind.deleted, i + 1, null, oldLines[i++]));
    }
  }
  return rows;
}

final class _Welcome extends StatelessWidget {
  const _Welcome({required this.onSearch, required this.onCreate});

  final VoidCallback onSearch;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xffeef0ff),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: OpenMuseTokens.accent,
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '从本地工作区开始',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 7),
          const Text(
            '文档保存在本机。编辑器、Viewer 与助手按需由插件激活。',
            textAlign: TextAlign.center,
            style: TextStyle(color: OpenMuseTokens.textMuted, height: 1.45),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('搜索资源'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建文档'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

final class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(backgroundColor: Colors.transparent),
      onPressed: onPressed,
      icon: Icon(icon, size: 17, color: OpenMuseTokens.textMuted),
    ),
  );
}

final class _FooterAction extends StatelessWidget {
  const _FooterAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: OpenMuseTokens.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: OpenMuseTokens.compactText.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showSearch(
  BuildContext context,
  LocalWorkspaceController workspace,
) => showDialog<void>(
  context: context,
  barrierColor: OpenMuseTokens.scrim,
  builder: (context) => _SearchDialog(workspace: workspace),
);

final class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.workspace});

  final LocalWorkspaceController workspace;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

final class _SearchDialogState extends State<_SearchDialog> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.workspace.search(query.text);
    return Dialog(
      alignment: const Alignment(0, -0.48),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: 780,
        height: 490,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索本地工作区…',
                  prefixIcon: const Icon(Icons.search, size: 19),
                  suffixIcon: IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xfffafafd),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: OpenMuseTokens.border),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Text(
                '本地资源',
                style: TextStyle(
                  fontSize: 12,
                  color: OpenMuseTokens.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Text(
                        '没有匹配的资源',
                        style: TextStyle(color: OpenMuseTokens.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final resource = results[index];
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                          leading: Icon(
                            _ResourceRow.iconFor(resource.extension),
                            size: 18,
                          ),
                          title: Text(resource.displayName),
                          subtitle: Text(
                            resource.uri.toFilePath(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            widget.workspace.select(resource);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _createDocument(
  BuildContext context,
  LocalWorkspaceController workspace,
) async {
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => const _CreateDocumentDialog(),
  );
  if (result == null || !context.mounted) return;
  try {
    await workspace.createMarkdown(result);
  } on FileSystemException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('无法创建文档：${error.message}')));
  }
}

final class _CreateDocumentDialog extends StatefulWidget {
  const _CreateDocumentDialog();

  @override
  State<_CreateDocumentDialog> createState() => _CreateDocumentDialogState();
}

final class _CreateDocumentDialogState extends State<_CreateDocumentDialog> {
  final name = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建本地文档'),
    content: SizedBox(
      width: 380,
      child: TextField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '名称',
          hintText: '未命名文档',
          suffixText: '.md',
          helperText: '文件会保存在当前本地工作区。',
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, name.text),
        child: const Text('创建'),
      ),
    ],
  );
}

Future<void> _showPlugins(
  BuildContext context,
  OpenMusePluginRegistry registry,
) => showDialog<void>(
  context: context,
  builder: (context) => _PluginDialog(registry: registry),
);

final class _PluginDialog extends StatelessWidget {
  const _PluginDialog({required this.registry});

  final OpenMusePluginRegistry registry;

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 700,
      height: 520,
      child: Column(
        children: [
          _DialogHeader(
            title: '插件',
            subtitle: '编辑器、Viewer 与助手由独立插件提供',
            onClose: () => Navigator.pop(context),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: registry,
              builder: (context, _) => ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: registry.descriptors.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final descriptor = registry.descriptors.elementAt(index);
                  final state = registry.stateOf(descriptor.id);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 7,
                      horizontal: 8,
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xfff0f1f7),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.extension_outlined,
                        size: 20,
                        color: OpenMuseTokens.accent,
                      ),
                    ),
                    title: Text(descriptor.name),
                    subtitle: Text(
                      '${descriptor.id}  ·  ${descriptor.version}  ·  ${descriptor.runtime.name}',
                    ),
                    trailing: _StatePill(state: state),
                  );
                },
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '外部插件安装与签名校验将在插件运行时门禁完成后开放。',
                style: TextStyle(fontSize: 12, color: OpenMuseTokens.textMuted),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});

  final OpenMusePluginState? state;

  @override
  Widget build(BuildContext context) {
    final active = state == OpenMusePluginState.active;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: active ? const Color(0xffe9f7ec) : const Color(0xfff0f1f5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? '运行中' : '已安装',
        style: TextStyle(
          fontSize: 11,
          color: active ? const Color(0xff267a3b) : OpenMuseTokens.textMuted,
        ),
      ),
    );
  }
}

final class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 15, 12, 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: OpenMuseTokens.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 19),
        ),
      ],
    ),
  );
}
