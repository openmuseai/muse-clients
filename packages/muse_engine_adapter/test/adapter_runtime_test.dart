import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_engine_adapter/muse_engine_adapter.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

void main() {
  late MuseEngineAdapterManifestV1 manifest;
  late MuseProbeRequestV1 request;
  late MuseProbeResultV1 result;
  setUpAll(() async {
    final fixtures =
        (jsonDecode(
                  await File(
                    '../../contracts/muse/contract-engine-session/v1/messages.json',
                  ).readAsString(),
                )
                as List)
            .cast<Map>();
    Map<String, Object?> value(String name) =>
        (fixtures.singleWhere(
                  (item) => item['name'].toString().startsWith(name),
                )['value']
                as Map)
            .cast<String, Object?>();
    manifest = MuseEngineAdapterManifestV1.fromJson(value('E-FX-001'));
    request = MuseProbeRequestV1.fromJson(value('E-FX-002'));
    result = MuseProbeResultV1.fromJson(value('E-FX-003'));
  });

  test(
    'registry isolates generations and exposes only latest matching candidate',
    () {
      final registry = MuseAdapterRegistry();
      final old = registry.register(
        _FakeAdapter(manifest, result),
        generation: 1,
      );
      registry.register(_FakeAdapter(manifest, result), generation: 2);
      expect(
        () => registry.register(_FakeAdapter(manifest, result), generation: 2),
        throwsStateError,
      );
      final candidates = registry.candidates(
        formatId: 'ooxml.word',
        os: 'macos',
        arch: 'arm64',
        placement: 'desktop-local',
      );
      expect(candidates.single.generation, 2);
      old.close();
      expect(registry.count, 1);
    },
  );

  test(
    'candidate matching uses verified format id and never extension hints',
    () {
      final registry = MuseAdapterRegistry()
        ..register(_FakeAdapter(manifest, result), generation: 1);
      expect(
        registry.candidates(
          formatId: 'docx',
          os: 'macos',
          arch: 'arm64',
          placement: 'desktop-local',
        ),
        isEmpty,
      );
      expect(
        registry.candidates(
          formatId: 'ooxml.word',
          os: 'macos',
          arch: 'arm64',
          placement: 'desktop-local',
        ),
        hasLength(1),
      );
    },
  );

  test('probe fan-out respects concurrency and cache dimensions', () async {
    var active = 0, maxActive = 0, calls = 0;
    final adapters = List.generate(5, (index) {
      final adapter = _FakeAdapter(
        manifest,
        result,
        onProbe: () async {
          calls++;
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
        },
      );
      return MuseAdapterRegistration(adapter: adapter, generation: index + 1);
    });
    final coordinator = MuseProbeCoordinator(
      concurrency: 2,
      clock: () => 1789466400000,
    );
    MuseProbeRequestV1 requestFor(MuseAdapterRegistration registration) =>
        request;
    await coordinator.probeAll(
      registrations: adapters,
      requestFor: requestFor,
      cancellation: MuseCancellationToken(),
    );
    expect(maxActive, 2);
    expect(calls, 5);
    final cachedRequest = MuseProbeRequestV1(
      probeRef: 'probe.cached',
      descriptor: request.descriptor,
      placement: request.placement,
      requestedMode: request.requestedMode,
      policyRevision: request.policyRevision,
      deadlineAt: request.deadlineAt,
      cancellationRef: 'cancel.cached',
    );
    final cached = await coordinator.probeAll(
      registrations: adapters,
      requestFor: (_) => cachedRequest,
      cancellation: MuseCancellationToken(),
    );
    expect(
      calls,
      5,
      reason: 'same runtime/policy/placement/generation must hit cache',
    );
    expect(
      cached.map((outcome) => outcome.result!.probeRef).toSet(),
      {'probe.cached'},
      reason: 'cache payload must be rebound to the current probe envelope',
    );
    final changed = MuseProbeRequestV1(
      probeRef: request.probeRef,
      descriptor: request.descriptor,
      placement: request.placement,
      requestedMode: request.requestedMode,
      policyRevision: 'policy.changed',
      deadlineAt: request.deadlineAt,
      cancellationRef: request.cancellationRef,
    );
    await coordinator.probeAll(
      registrations: adapters,
      requestFor: (_) => changed,
      cancellation: MuseCancellationToken(),
    );
    expect(calls, 10);
  });

  test('cancellation prevents queued probes from starting', () async {
    final token = MuseCancellationToken();
    var calls = 0;
    final adapter = _FakeAdapter(
      manifest,
      result,
      onProbe: () async {
        calls++;
        token.cancel();
      },
    );
    final registrations = List.generate(
      4,
      (index) =>
          MuseAdapterRegistration(adapter: adapter, generation: index + 1),
    );
    await expectLater(
      MuseProbeCoordinator(concurrency: 1).probeAll(
        registrations: registrations,
        requestFor: (_) => request,
        cancellation: token,
      ),
      throwsA(isA<MuseAdapterException>()),
    );
    expect(calls, 1);
  });

  test('router scores capability quality and makes downgrade explicit', () {
    final adapter = _FakeAdapter(manifest, result);
    final registration = MuseAdapterRegistration(
      adapter: adapter,
      generation: 1,
    );
    final selection = const MuseEngineRouter().select(
      outcomes: [
        MuseProbeOutcome(
          registration: registration,
          result: null,
          errorCode: 'not used',
        ),
      ],
      requestedMode: MuseRequestedMode.preferEdit,
      policy: const MuseRoutePolicy(revision: 'p'),
    );
    expect(selection, isNull);
    final routed = const MuseEngineRouter().select(
      outcomes: [MuseProbeOutcome(registration: registration, result: null)],
      requestedMode: MuseRequestedMode.view,
      policy: const MuseRoutePolicy(
        revision: 'p',
        deniedAdapterRefs: {'muse.ioffice.word~1.0.0'},
      ),
    );
    expect(routed, isNull);
    final success = const MuseEngineRouter().select(
      outcomes: [
        MuseProbeOutcome(
          registration: registration,
          result: _ResultHolder.value,
        ),
      ],
      requestedMode: MuseRequestedMode.preferEdit,
      policy: const MuseRoutePolicy(revision: 'p'),
    );
    expect(success!.effectiveMode, MuseEngineMode.ephemeralEdit);
    expect(success.reasonCodes, contains('MODE_DOWNGRADED'));
  });
}

final class _ResultHolder {
  static final value = MuseProbeResultV1(
    probeRef: 'probe',
    available: true,
    effectiveModes: const [MuseEngineMode.view, MuseEngineMode.ephemeralEdit],
    materializationKinds: const [MuseMaterializationKind.bytesHandle],
    maxBytes: 1024,
    quality: const MuseProbeQualityV1(
      fidelity: MuseFidelity.nativePartial,
      startupClass: MuseStartupClass.warmMedium,
    ),
    warnings: const [],
    probeDigest: 'sha256:test',
    expiresAt: 9999999999999,
  );
}

final class _FakeAdapter implements MuseEngineAdapter {
  _FakeAdapter(this.manifest, this.result, {this.onProbe});
  @override
  final MuseEngineAdapterManifestV1 manifest;
  final MuseProbeResultV1 result;
  final Future<void> Function()? onProbe;
  @override
  Future<MuseProbeResultV1> probe(
    MuseProbeRequestV1 request,
    MuseCancellationToken cancellation,
  ) async {
    await onProbe?.call();
    return MuseProbeResultV1(
      probeRef: request.probeRef,
      available: result.available,
      effectiveModes: result.effectiveModes,
      materializationKinds: result.materializationKinds,
      maxBytes: result.maxBytes,
      quality: result.quality,
      warnings: result.warnings,
      probeDigest: result.probeDigest,
      expiresAt: result.expiresAt,
    );
  }

  @override
  Future<MuseEngineSessionHandleV1> open(
    MuseOpenEngineSessionRequestV1 request,
    MuseCancellationToken cancellation,
  ) => throw UnimplementedError();
  @override
  Future<void> focus(MuseEngineSessionHandleV1 session) async {}
  @override
  Future<void> close(
    MuseEngineSessionHandleV1 session, {
    required String reason,
  }) async {}
}
