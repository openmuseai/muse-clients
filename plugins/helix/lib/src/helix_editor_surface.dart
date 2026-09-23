import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:xterm/xterm.dart';

import 'helix_runtime.dart';

final class HelixEditorSurface extends StatefulWidget {
  const HelixEditorSurface({
    super.key,
    required this.runtime,
    required this.resource,
  });

  final HelixRuntimePool runtime;
  final OpenMuseResource resource;

  @override
  State<HelixEditorSurface> createState() => _HelixEditorSurfaceState();
}

final class _HelixEditorSurfaceState extends State<HelixEditorSurface> {
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(covariant HelixEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource.uri != widget.resource.uri) unawaited(_open());
  }

  Future<void> _open() async {
    if (!widget.resource.uri.isScheme('file')) return;
    try {
      await widget.runtime.openDocument(widget.resource.uri.toFilePath());
    } catch (_) {
      // The runtime exposes its structured failure state below.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.runtime,
      builder: (context, _) => ColoredBox(
        color: widget.runtime.preferences.terminalTheme.background,
        child: Stack(
          children: [
            Positioned.fill(
              child: TerminalView(
                widget.runtime.terminal,
                theme: widget.runtime.preferences.terminalTheme,
                textStyle: widget.runtime.preferences.terminalStyle,
                keyboardAppearance: widget.runtime.preferences.dark
                    ? Brightness.dark
                    : Brightness.light,
                autofocus: true,
              ),
            ),
            if (widget.runtime.lastError case final error?)
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xff2c2023),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$error',
                    style: const TextStyle(color: Color(0xffffb4ab)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
