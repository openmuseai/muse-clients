import 'package:flutter_test/flutter_test.dart';
import 'package:muse_resource_bridge/muse_resource_bridge.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

void main() {
  test('request/status/cancel share one neutral Host Bridge envelope', () {
    final request = MusePresentationRequestV2(
      requestRef: 'preq.1',
      resourceRef: 'resource.1',
      disposition: MusePresentationDisposition.open,
      requestedMode: MuseRequestedMode.view,
      placementHint: MusePlacementHint.currentWindow,
      cause: const MusePresentationCauseV2(kind: 'dsh-card'),
      requestedAt: 1,
    );
    final values = [
      MusePresentationBridgeEnvelope(
        requestId: 'wire.1',
        method: MusePresentationBridgeMethod.request,
        workspaceRef: 'workspace.1',
        actorRef: 'actor.1',
        payload: MuseBridgeRequestPayload(request),
      ),
      const MusePresentationBridgeEnvelope(
        requestId: 'wire.2',
        method: MusePresentationBridgeMethod.status,
        workspaceRef: 'workspace.1',
        actorRef: 'actor.1',
        payload: MuseBridgeStatusPayload('preq.1'),
      ),
      const MusePresentationBridgeEnvelope(
        requestId: 'wire.3',
        method: MusePresentationBridgeMethod.cancel,
        workspaceRef: 'workspace.1',
        actorRef: 'actor.1',
        payload: MuseBridgeCancelPayload('preq.1'),
      ),
    ];
    for (final value in values) {
      value.validateSize(MuseClientCapabilityProfile.mobile);
      expect(
        MusePresentationBridgeEnvelope.fromJson(value.toJson()).toJson(),
        value.toJson(),
      );
      expect(value.toJson().toString(), isNot(contains('engineId')));
    }
  });
  test('unknown engine-specific message fields fail closed', () {
    expect(
      () => MusePresentationBridgeEnvelope.fromJson({
        'protocol': 'muse.host-bridge/envelope/v1',
        'requestId': '1',
        'capability': 'resource.presentation',
        'method': 'status',
        'workspaceRef': 'w',
        'actorRef': 'a',
        'payload': {'requestRef': 'p'},
        'viewer-open': true,
      }),
      throwsA(isA<MuseDataPlaneException>()),
    );
  });
  test('web grants require exact audience, HTTPS origin and live TTL', () {
    var now = 1000;
    final broker = MuseDataPlaneBroker(
      profile: MuseClientCapabilityProfile.web,
      expectedAudience: 'viewer.web',
      allowedOrigins: {'https://viewer.muse.test'},
      clock: () => now,
    );
    MuseRemoteMaterializationGrant grant({
      String audience = 'viewer.web',
      String origin = 'https://viewer.muse.test',
      int expiresAt = 2000,
    }) => MuseRemoteMaterializationGrant(
      handleRef: 'h1',
      resourceRef: 'r1',
      revision: 'rev1',
      kind: MuseMaterializationKind.remoteUrl,
      accessMode: MuseAccessMode.read,
      audience: audience,
      origin: origin,
      expiresAt: expiresAt,
      sizeBytes: 10,
      rangeEnabled: true,
      generation: 1,
    );
    broker.admit(grant());
    expect(
      broker.authorize('h1', resourceRef: 'r1', generation: 1).revision,
      'rev1',
    );
    broker.revoke('h1');
    expect(broker.activeGrantCount, 0);
    expect(
      () => broker.admit(grant(audience: 'other')),
      throwsA(isA<MuseDataPlaneException>()),
    );
    expect(
      () => broker.admit(grant(origin: 'http://viewer.muse.test')),
      throwsA(isA<MuseDataPlaneException>()),
    );
    now = 3000;
    expect(() => broker.admit(grant()), throwsA(isA<MuseDataPlaneException>()));
  });
  test('mobile profile is view-only and enforces low-memory size ceiling', () {
    expect(MuseClientCapabilityProfile.mobile.allowedModes, {
      MuseEngineMode.view,
    });
    final broker = MuseDataPlaneBroker(
      profile: MuseClientCapabilityProfile.mobile,
      expectedAudience: 'mobile',
      allowedOrigins: {'https://resource.muse.test'},
    );
    final grant = MuseRemoteMaterializationGrant(
      handleRef: 'large',
      resourceRef: 'r',
      revision: 'rev',
      kind: MuseMaterializationKind.remoteUrl,
      accessMode: MuseAccessMode.read,
      audience: 'mobile',
      origin: 'https://resource.muse.test',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 10000,
      sizeBytes: MuseClientCapabilityProfile.mobile.maxResourceBytes + 1,
      rangeEnabled: true,
      generation: 1,
    );
    expect(() => broker.admit(grant), throwsA(isA<MuseDataPlaneException>()));
  });
  test('generation revoke invalidates all remote reads', () {
    final broker = MuseDataPlaneBroker(
      profile: MuseClientCapabilityProfile.desktop,
      expectedAudience: 'desktop.viewer',
      allowedOrigins: {'http://127.0.0.1:43121'},
    );
    final grant = MuseRemoteMaterializationGrant(
      handleRef: 'loop',
      resourceRef: 'r',
      revision: 'rev',
      kind: MuseMaterializationKind.loopbackUrl,
      accessMode: MuseAccessMode.read,
      audience: 'desktop.viewer',
      origin: 'http://127.0.0.1:43121',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 10000,
      sizeBytes: 1,
      rangeEnabled: true,
      generation: 7,
    );
    broker.admit(grant);
    broker.revokeGeneration(7);
    expect(
      () => broker.authorize('loop', resourceRef: 'r', generation: 7),
      throwsA(isA<MuseDataPlaneException>()),
    );
  });
}
