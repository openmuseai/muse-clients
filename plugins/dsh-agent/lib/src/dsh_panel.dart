import 'package:flutter/material.dart';

import 'dsh_sidecar.dart';
import 'dsh_web_view.dart';

final class DshPanel extends StatefulWidget {
  const DshPanel({
    super.key,
    required this.supervisor,
    required this.onOpenResource,
  });
  final DshSidecarSupervisor supervisor;
  final Future<void> Function(DshResourceOpenMessage request) onOpenResource;

  @override
  State<DshPanel> createState() => _DshPanelState();
}

final class _DshPanelState extends State<DshPanel> {
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_start);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.supervisor,
      builder: (context, _) => ColoredBox(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff202228)
            : const Color(0xfffbfbfc),
        child: Column(
          children: [
            _AgentHeader(onReload: () => setState(() => _reloadToken++)),
            Expanded(
              child: _PanelBody(
                supervisor: widget.supervisor,
                onOpenResource: widget.onOpenResource,
                reloadToken: _reloadToken,
              ),
            ),
            if (widget.supervisor.state != DshSidecarState.ready)
              _Composer(onStart: _start),
          ],
        ),
      ),
    );
  }

  Future<void> _start() async {
    try {
      await widget.supervisor.ensureStarted();
    } catch (_) {
      // State and redacted diagnostics remain inside the plugin panel.
    }
  }
}

final class _AgentHeader extends StatelessWidget {
  const _AgentHeader({required this.onReload});
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              color: Theme.of(context).colorScheme.onSurface,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'DSH Agent',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '刷新 DSH 面板',
              onPressed: onReload,
              icon: Icon(
                Icons.refresh,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 16,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
        const SizedBox(height: 11),
        const Text(
          '对话',
          style: TextStyle(color: Color(0xff2f6de1), fontSize: 12),
        ),
      ],
    ),
  );
}

final class _PanelBody extends StatelessWidget {
  const _PanelBody({
    required this.supervisor,
    required this.onOpenResource,
    required this.reloadToken,
  });
  final DshSidecarSupervisor supervisor;
  final Future<void> Function(DshResourceOpenMessage request) onOpenResource;
  final int reloadToken;

  @override
  Widget build(BuildContext context) {
    if (supervisor.state == DshSidecarState.ready) {
      return DshWebView(
        url: supervisor.endpoint!,
        onOpenResource: onOpenResource,
        reloadToken: reloadToken,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agent 可选组件',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _friendlyError(supervisor.lastError) ??
                    '仅在首次使用时启动 DSH sidecar；它不会阻塞本地 Workspace。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    context.findAncestorStateOfType<_DshPanelState>()?._start(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xff2f6de1),
                  padding: EdgeInsets.zero,
                ),
                child: const Text('启动插件'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Composer extends StatelessWidget {
  const _Composer({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
    padding: const EdgeInsets.fromLTRB(12, 11, 10, 9),
    height: 82,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '给智能体发消息',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const Spacer(),
        Row(
          children: [
            const Icon(Icons.add, color: Color(0xff777b84), size: 18),
            const Spacer(),
            IconButton(
              onPressed: onStart,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              icon: const Icon(Icons.arrow_upward, size: 16),
              color: const Color(0xffdfe5ff),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xff496bb8),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

String? _friendlyError(Object? error) {
  if (error == null) return null;
  return error.toString().replaceFirst(
    RegExp(r'^(Bad state|StateError):\s*'),
    '',
  );
}
