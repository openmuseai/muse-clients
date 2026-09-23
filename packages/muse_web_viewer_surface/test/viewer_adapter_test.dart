import 'package:flutter_test/flutter_test.dart';
import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_resource_bridge/muse_resource_bridge.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';
import 'package:muse_web_viewer_surface/muse_web_viewer_surface.dart';

void main() {
  test('Wave 1 manifest exposes only certified text/image/PDF view', () {
    final adapter = _adapter();
    expect(adapter.manifest.formats.map((e) => e.formatId), [
      'document.pdf',
      'image.raster',
      'text.plain',
    ]);
    expect(
      adapter.manifest.formats.map((e) => e.formatId),
      isNot(contains('ooxml.word')),
    );
    expect(adapter.manifest.modes, [MuseEngineMode.view]);
    expect(
      adapter.manifest.capabilities,
      isNot(contains(MuseAdapterCapability.commit)),
    );
  });
  test(
    'probe rejects active content, edit and implicit network runtime',
    () async {
      final adapter = _adapter();
      final token = MuseCancellationToken();
      expect(
        (await adapter.probe(
          _probe(active: MuseActiveContent.none),
          token,
        )).available,
        isTrue,
      );
      expect(
        (await adapter.probe(
          _probe(active: MuseActiveContent.present),
          token,
        )).available,
        isFalse,
      );
      expect(
        (await adapter.probe(
          _probe(active: MuseActiveContent.none, mode: MuseRequestedMode.edit),
          token,
        )).available,
        isFalse,
      );
      final network = _adapter(
        health: const MuseViewerRuntimeHealth(
          bundleReady: true,
          workerReady: true,
          implicitNetworkRequests: true,
          runtimeDigest: 'bad',
        ),
      );
      expect(
        (await network.probe(
          _probe(active: MuseActiveContent.none),
          token,
        )).available,
        isFalse,
      );
    },
  );
  test(
    'isolated bridge rejects wrong origin nonce generation and late messages',
    () {
      final bridge = MuseViewerBridgeSession(
        origin: 'https://viewer.muse.test',
        nonce: 'n1',
        generation: 2,
      );
      final message = <String, Object?>{
        'protocol': 'muse.viewer-bridge/v1',
        'nonce': 'n1',
        'generation': 2,
        'type': 'viewer.ready',
      };
      expect(
        bridge.receive(sourceOrigin: 'https://evil.test', message: message),
        isNull,
      );
      expect(
        bridge.receive(
          sourceOrigin: 'https://viewer.muse.test',
          message: {...message, 'nonce': 'bad'},
        ),
        isNull,
      );
      expect(
        bridge.receive(
          sourceOrigin: 'https://viewer.muse.test',
          message: {...message, 'generation': 1},
        ),
        isNull,
      );
      expect(
        bridge
            .receive(
              sourceOrigin: 'https://viewer.muse.test',
              message: message,
            )!
            .type,
        'viewer.ready',
      );
      bridge.close();
      expect(
        bridge.receive(
          sourceOrigin: 'https://viewer.muse.test',
          message: message,
        ),
        isNull,
      );
    },
  );
  test('open/focus/close destroys the vendor surface exactly once', () async {
    final runtime = _Runtime();
    final adapter = _adapter(runtime: runtime);
    final request = MuseOpenEngineSessionRequestV1(
      requestRef: 'p',
      attemptRef: 'a',
      resourceRef: 'r',
      baseRevision: 'rev',
      mode: MuseEngineMode.view,
      materialization: const MuseOpenMaterializationV1(
        kind: MuseMaterializationKind.remoteUrl,
        handleRef: 'h',
        expiresAt: 9999999999999,
      ),
      surface: const MuseOpenSurfaceV1(
        windowRef: 'w',
        placement: 'main',
        reuse: 'compatible',
      ),
      generation: 1,
    );
    final handle = await adapter.open(request, MuseCancellationToken());
    await adapter.focus(handle);
    await adapter.close(handle, reason: 'test');
    await adapter.close(handle, reason: 'duplicate');
    expect(runtime.session.focusCalls, 1);
    expect(runtime.session.destroyCalls, 1);
    expect(adapter.liveSessionCount, 0);
  });
}

MuseOpenFileViewerAdapter _adapter({
  MuseViewerRuntimeHealth health = const MuseViewerRuntimeHealth(
    bundleReady: true,
    workerReady: true,
    implicitNetworkRequests: false,
    runtimeDigest: 'sha256:viewer',
  ),
  _Runtime? runtime,
}) => MuseOpenFileViewerAdapter(
  runtime: runtime ?? _Runtime(health: health),
  catalog: MuseViewerCertificationCatalog.wave1(),
  profile: MuseClientCapabilityProfile.web,
);
MuseProbeRequestV1 _probe({
  required MuseActiveContent active,
  MuseRequestedMode mode = MuseRequestedMode.view,
}) => MuseProbeRequestV1(
  probeRef: 'probe',
  descriptor: MuseProbeDescriptorV1(
    resourceRef: 'r',
    revision: 'rev',
    format: const MuseResourceFormat(
      formatId: 'document.pdf',
      confidence: MuseFormatConfidence.verified,
    ),
    sizeBytes: 100,
    security: MuseResourceSecurity(
      classification: MuseSecurityClassification.internal,
      activeContent: active,
    ),
  ),
  placement: const MuseProbePlacementV1(
    kind: MusePlacementKind.webRemote,
    os: 'web',
    arch: 'wasm32',
    memoryBudgetBytes: 1000000,
    gpu: false,
  ),
  requestedMode: mode,
  policyRevision: 'p',
  deadlineAt: 9999999999999,
  cancellationRef: 'c',
);

final class _Runtime implements MuseViewerRuntime {
  _Runtime({MuseViewerRuntimeHealth? health})
    : healthValue =
          health ??
          const MuseViewerRuntimeHealth(
            bundleReady: true,
            workerReady: true,
            implicitNetworkRequests: false,
            runtimeDigest: 'sha256:viewer',
          );
  final MuseViewerRuntimeHealth healthValue;
  final session = _Session();
  @override
  Future<MuseViewerRuntimeHealth> health() async => healthValue;
  @override
  Future<MuseViewerRuntimeSession> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  ) async => session;
}

final class _Session implements MuseViewerRuntimeSession {
  @override
  String get sessionRef => 'viewer.session';
  @override
  String get surfaceInstanceRef => 'viewer.surface';
  int focusCalls = 0, destroyCalls = 0;
  @override
  Future<void> focus() async {
    focusCalls++;
  }

  @override
  Future<void> destroy() async {
    destroyCalls++;
  }
}
