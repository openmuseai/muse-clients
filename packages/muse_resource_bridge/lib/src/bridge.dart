import 'dart:convert';

import 'package:muse_resource_contract/muse_resource_contract.dart';

import 'data_plane.dart';
import 'profile.dart';

enum MusePresentationBridgeMethod { request, status, cancel }

sealed class MusePresentationBridgePayload {
  const MusePresentationBridgePayload();
  Map<String, Object?> toJson();
}

final class MuseBridgeRequestPayload extends MusePresentationBridgePayload {
  const MuseBridgeRequestPayload(this.request);
  final MusePresentationRequestV2 request;
  @override
  Map<String, Object?> toJson() => request.toJson();
}

final class MuseBridgeStatusPayload extends MusePresentationBridgePayload {
  const MuseBridgeStatusPayload(this.requestRef);
  final String requestRef;
  @override
  Map<String, Object?> toJson() => {'requestRef': requestRef};
}

final class MuseBridgeCancelPayload extends MusePresentationBridgePayload {
  const MuseBridgeCancelPayload(this.requestRef);
  final String requestRef;
  @override
  Map<String, Object?> toJson() => {'requestRef': requestRef};
}

final class MusePresentationBridgeEnvelope {
  const MusePresentationBridgeEnvelope({
    required this.requestId,
    required this.method,
    required this.workspaceRef,
    required this.actorRef,
    required this.payload,
  });
  final String requestId, workspaceRef, actorRef;
  final MusePresentationBridgeMethod method;
  final MusePresentationBridgePayload payload;
  factory MusePresentationBridgeEnvelope.fromJson(Map<String, Object?> map) {
    const keys = {
      'protocol',
      'requestId',
      'capability',
      'method',
      'workspaceRef',
      'actorRef',
      'payload',
    };
    if (map.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(map.keys.toSet()).isNotEmpty)
      throw const MuseDataPlaneException('INVALID_ENVELOPE_FIELDS');
    if (map['protocol'] != 'muse.host-bridge/envelope/v1' ||
        map['capability'] != 'resource.presentation')
      throw const MuseDataPlaneException('INVALID_ENVELOPE_PROTOCOL');
    final requestId = map['requestId'],
        workspaceRef = map['workspaceRef'],
        actorRef = map['actorRef'],
        methodRaw = map['method'],
        raw = map['payload'];
    if (requestId is! String ||
        workspaceRef is! String ||
        actorRef is! String ||
        methodRaw is! String ||
        raw is! Map)
      throw const MuseDataPlaneException('INVALID_ENVELOPE_TYPE');
    final payloadMap = raw.cast<String, Object?>();
    final method = switch (methodRaw) {
      'request' => MusePresentationBridgeMethod.request,
      'status' => MusePresentationBridgeMethod.status,
      'cancel' => MusePresentationBridgeMethod.cancel,
      _ => throw const MuseDataPlaneException('INVALID_METHOD'),
    };
    final payload = switch (method) {
      MusePresentationBridgeMethod.request => MuseBridgeRequestPayload(
        MusePresentationRequestV2.fromJson(payloadMap),
      ),
      MusePresentationBridgeMethod.status => MuseBridgeStatusPayload(
        _onlyRequestRef(payloadMap),
      ),
      MusePresentationBridgeMethod.cancel => MuseBridgeCancelPayload(
        _onlyRequestRef(payloadMap),
      ),
    };
    return MusePresentationBridgeEnvelope(
      requestId: requestId,
      method: method,
      workspaceRef: workspaceRef,
      actorRef: actorRef,
      payload: payload,
    );
  }
  Map<String, Object?> toJson() => {
    'protocol': 'muse.host-bridge/envelope/v1',
    'requestId': requestId,
    'capability': 'resource.presentation',
    'method': method.name,
    'workspaceRef': workspaceRef,
    'actorRef': actorRef,
    'payload': payload.toJson(),
  };
  void validateSize(MuseClientCapabilityProfile profile) {
    if (utf8.encode(jsonEncode(toJson())).length > profile.maxEnvelopeBytes)
      throw const MuseDataPlaneException('ENVELOPE_TOO_LARGE');
  }

  static String _onlyRequestRef(Map<String, Object?> map) {
    if (map.keys.toSet().difference({'requestRef'}).isNotEmpty ||
        map.length != 1 ||
        map['requestRef'] is! String)
      throw const MuseDataPlaneException('INVALID_REQUEST_REF_PAYLOAD');
    return map['requestRef']! as String;
  }
}
