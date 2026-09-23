import 'package:muse_resource_bridge/muse_resource_bridge.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

import 'orchestrator.dart';

final class MusePresentationHostResponse {
  const MusePresentationHostResponse({
    required this.requestId,
    required this.requestRef,
    required this.phase,
    this.decision,
    this.receipt,
  });
  final String requestId, requestRef;
  final MusePresentationPhase phase;
  final MuseRouteDecisionV2? decision;
  final MusePresentationReceiptV2? receipt;
  bool get terminal => phase == MusePresentationPhase.terminal;
  Map<String, Object?> toJson() => {
    'protocol': 'muse.presentation/host-response/v1',
    'requestId': requestId,
    'requestRef': requestRef,
    'phase': phase.name,
    'terminal': terminal,
    if (decision != null) 'decision': decision!.toJson(),
    if (receipt != null) 'receipt': receipt!.toJson(),
  };
}

final class MusePresentationHostService {
  const MusePresentationHostService(this.orchestrator);
  final MuseSurfaceOrchestrator orchestrator;
  Future<MusePresentationHostResponse> handle(
    MusePresentationBridgeEnvelope envelope,
  ) async {
    switch (envelope.method) {
      case MusePresentationBridgeMethod.request:
        final payload = envelope.payload as MuseBridgeRequestPayload;
        final operation = orchestrator.request(payload.request);
        final status = orchestrator.status(operation.request.requestRef)!;
        return _response(envelope.requestId, status);
      case MusePresentationBridgeMethod.status:
        final payload = envelope.payload as MuseBridgeStatusPayload;
        final status = orchestrator.status(payload.requestRef);
        if (status == null)
          throw const MuseOrchestratorException('REQUEST_NOT_FOUND');
        return _response(envelope.requestId, status);
      case MusePresentationBridgeMethod.cancel:
        final payload = envelope.payload as MuseBridgeCancelPayload;
        await orchestrator.cancel(payload.requestRef);
        return _response(
          envelope.requestId,
          orchestrator.status(payload.requestRef)!,
        );
    }
  }

  MusePresentationHostResponse _response(
    String requestId,
    MusePresentationStatus status,
  ) => MusePresentationHostResponse(
    requestId: requestId,
    requestRef: status.requestRef,
    phase: status.phase,
    decision: status.decision,
    receipt: status.receipt,
  );
}
