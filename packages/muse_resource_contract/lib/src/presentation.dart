import 'wire.dart';

enum MuseRequestedMode { view, preferEdit, edit }

enum MuseEffectiveMode { view, ephemeralEdit, edit }

enum MusePlacementHint { currentWindow, newWindow, sidePanel, background }

enum MusePresentationDisposition { open, focus }

enum MusePresentationResult {
  opened,
  focused,
  fallback,
  unsupported,
  cancelled,
  denied,
  failed,
}

final class MuseAnchorHintV1 {
  MuseAnchorHintV1({required this.provider, required Object? value})
    : value = deepCopy(value);
  final String provider;
  final Object? value;
  factory MuseAnchorHintV1.fromJson(Object? value) {
    final map = objectMap(value, 'anchorHint');
    requireKeys(map, required: {'provider', 'value'});
    return MuseAnchorHintV1(
      provider: stringField(map, 'provider'),
      value: map['value'],
    );
  }
  Map<String, Object?> toJson() => {
    'provider': provider,
    'value': deepCopy(value),
  };
}

final class MusePresentationCauseV2 {
  const MusePresentationCauseV2({
    required this.kind,
    this.sessionRef,
    this.eventRef,
  });
  final String kind;
  final String? sessionRef, eventRef;
  factory MusePresentationCauseV2.fromJson(Object? value) {
    final map = objectMap(value, 'cause');
    requireKeys(map, required: {'kind'}, optional: {'sessionRef', 'eventRef'});
    final kind = stringField(map, 'kind');
    if (!{
      'user',
      'dsh-deliverable',
      'dsh-mention',
      'dsh-card',
      'agent-tool',
      'restore',
    }.contains(kind)) {
      throw MuseContractFormatException(
        'cause.kind has unsupported value $kind',
      );
    }
    return MusePresentationCauseV2(
      kind: kind,
      sessionRef: optionalString(map, 'sessionRef'),
      eventRef: optionalString(map, 'eventRef'),
    );
  }
  Map<String, Object?> toJson() => {
    'kind': kind,
    if (sessionRef != null) 'sessionRef': sessionRef,
    if (eventRef != null) 'eventRef': eventRef,
  };
}

final class MusePresentationRequestV2 {
  const MusePresentationRequestV2({
    required this.requestRef,
    required this.resourceRef,
    required this.disposition,
    required this.requestedMode,
    required this.placementHint,
    required this.cause,
    required this.requestedAt,
    this.anchorHint,
  });
  final String requestRef, resourceRef;
  final MusePresentationDisposition disposition;
  final MuseRequestedMode requestedMode;
  final MuseAnchorHintV1? anchorHint;
  final MusePlacementHint placementHint;
  final MusePresentationCauseV2 cause;
  final int requestedAt;
  factory MusePresentationRequestV2.fromJson(Map<String, Object?> map) {
    requireProtocol(map, 'muse.presentation/request/v2');
    requireKeys(
      map,
      required: {
        'protocol',
        'requestRef',
        'resourceRef',
        'disposition',
        'requestedMode',
        'placementHint',
        'cause',
        'requestedAt',
      },
      optional: {'anchorHint'},
    );
    return MusePresentationRequestV2(
      requestRef: stringField(map, 'requestRef'),
      resourceRef: stringField(map, 'resourceRef'),
      disposition: enumField(
        map,
        'disposition',
        MusePresentationDisposition.values,
      ),
      requestedMode: enumField(map, 'requestedMode', MuseRequestedMode.values),
      anchorHint: map['anchorHint'] == null
          ? null
          : MuseAnchorHintV1.fromJson(map['anchorHint']),
      placementHint: enumField(map, 'placementHint', MusePlacementHint.values),
      cause: MusePresentationCauseV2.fromJson(map['cause']),
      requestedAt: intField(map, 'requestedAt'),
    );
  }
  Map<String, Object?> toJson() => {
    'protocol': 'muse.presentation/request/v2',
    'requestRef': requestRef,
    'resourceRef': resourceRef,
    'disposition': enumWire(disposition),
    'requestedMode': enumWire(requestedMode),
    if (anchorHint != null) 'anchorHint': anchorHint!.toJson(),
    'placementHint': enumWire(placementHint),
    'cause': cause.toJson(),
    'requestedAt': requestedAt,
  };
}

final class MuseRouteCandidateV2 {
  const MuseRouteCandidateV2({
    required this.adapterRef,
    required this.available,
    required this.effectiveModes,
    required this.score,
    required this.reasonCodes,
  });
  final String adapterRef;
  final bool available;
  final List<MuseEffectiveMode> effectiveModes;
  final int score;
  final List<String> reasonCodes;
  factory MuseRouteCandidateV2.fromJson(Object? value) {
    final map = objectMap(value, 'candidate');
    requireKeys(
      map,
      required: {
        'adapterRef',
        'available',
        'effectiveModes',
        'score',
        'reasonCodes',
      },
    );
    final reasons = stringList(map, 'reasonCodes');
    _validateReasonCodes(reasons);
    return MuseRouteCandidateV2(
      adapterRef: stringField(map, 'adapterRef'),
      available: boolField(map, 'available'),
      effectiveModes: enumList(map, 'effectiveModes', MuseEffectiveMode.values),
      score: intField(map, 'score'),
      reasonCodes: reasons,
    );
  }
  Map<String, Object?> toJson() => {
    'adapterRef': adapterRef,
    'available': available,
    'effectiveModes': effectiveModes.map(enumWire).toList(),
    'score': score,
    'reasonCodes': reasonCodes,
  };
}

final class MuseRouteDecisionV2 {
  const MuseRouteDecisionV2({
    required this.decisionRef,
    required this.requestRef,
    required this.attemptRef,
    required this.selectedAdapterRef,
    required this.effectiveMode,
    required this.reasonCodes,
    required this.alternatives,
    required this.decidedAt,
  });
  final String decisionRef, requestRef, attemptRef, selectedAdapterRef;
  final MuseEffectiveMode effectiveMode;
  final List<String> reasonCodes;
  final List<MuseRouteCandidateV2> alternatives;
  final int decidedAt;
  factory MuseRouteDecisionV2.fromJson(Map<String, Object?> map) {
    requireProtocol(map, 'muse.presentation/route-decision/v2');
    requireKeys(
      map,
      required: {
        'protocol',
        'decisionRef',
        'requestRef',
        'attemptRef',
        'selectedAdapterRef',
        'effectiveMode',
        'reasonCodes',
        'alternatives',
        'decidedAt',
      },
    );
    final reasons = stringList(map, 'reasonCodes');
    _validateReasonCodes(reasons);
    return MuseRouteDecisionV2(
      decisionRef: stringField(map, 'decisionRef'),
      requestRef: stringField(map, 'requestRef'),
      attemptRef: stringField(map, 'attemptRef'),
      selectedAdapterRef: stringField(map, 'selectedAdapterRef'),
      effectiveMode: enumField(map, 'effectiveMode', MuseEffectiveMode.values),
      reasonCodes: reasons,
      alternatives: objectList(
        map['alternatives'],
        'alternatives',
      ).map(MuseRouteCandidateV2.fromJson).toList(),
      decidedAt: intField(map, 'decidedAt'),
    );
  }
  Map<String, Object?> toJson() => {
    'protocol': 'muse.presentation/route-decision/v2',
    'decisionRef': decisionRef,
    'requestRef': requestRef,
    'attemptRef': attemptRef,
    'selectedAdapterRef': selectedAdapterRef,
    'effectiveMode': enumWire(effectiveMode),
    'reasonCodes': reasonCodes,
    'alternatives': alternatives.map((e) => e.toJson()).toList(),
    'decidedAt': decidedAt,
  };
}

sealed class MusePresentationReceiptV2 {
  const MusePresentationReceiptV2({
    required this.receiptRef,
    required this.requestRef,
    required this.attemptRef,
    required this.completedAt,
    required this.traceRef,
  });
  final String receiptRef, requestRef, attemptRef, traceRef;
  final int completedAt;
  MusePresentationResult get result;
  Map<String, Object?> toJson();
  Map<String, Object?> baseJson() => {
    'protocol': 'muse.presentation/receipt/v2',
    'receiptRef': receiptRef,
    'requestRef': requestRef,
    'attemptRef': attemptRef,
    'completedAt': completedAt,
    'traceRef': traceRef,
  };
  factory MusePresentationReceiptV2.fromJson(Map<String, Object?> map) {
    requireProtocol(map, 'muse.presentation/receipt/v2');
    final result = enumField(map, 'result', MusePresentationResult.values);
    final base = {
      'protocol',
      'receiptRef',
      'requestRef',
      'attemptRef',
      'completedAt',
      'traceRef',
      'result',
    };
    if ({
      MusePresentationResult.opened,
      MusePresentationResult.focused,
      MusePresentationResult.fallback,
    }.contains(result)) {
      requireKeys(
        map,
        required: base.union({
          'effectiveMode',
          'selectedAdapterRef',
          'resourceRef',
          'revision',
          'sessionRef',
          'surfaceInstanceRef',
          'warnings',
        }),
      );
      return MusePresentationSuccessReceiptV2(
        receiptRef: stringField(map, 'receiptRef'),
        requestRef: stringField(map, 'requestRef'),
        attemptRef: stringField(map, 'attemptRef'),
        completedAt: intField(map, 'completedAt'),
        traceRef: stringField(map, 'traceRef'),
        result: result,
        effectiveMode: enumField(
          map,
          'effectiveMode',
          MuseEffectiveMode.values,
        ),
        selectedAdapterRef: stringField(map, 'selectedAdapterRef'),
        resourceRef: stringField(map, 'resourceRef'),
        revision: stringField(map, 'revision'),
        sessionRef: stringField(map, 'sessionRef'),
        surfaceInstanceRef: stringField(map, 'surfaceInstanceRef'),
        warnings: stringList(map, 'warnings'),
      );
    }
    requireKeys(map, required: base.union({'errorCode', 'retryable'}));
    return MusePresentationFailureReceiptV2(
      receiptRef: stringField(map, 'receiptRef'),
      requestRef: stringField(map, 'requestRef'),
      attemptRef: stringField(map, 'attemptRef'),
      completedAt: intField(map, 'completedAt'),
      traceRef: stringField(map, 'traceRef'),
      result: result,
      errorCode: stringField(map, 'errorCode'),
      retryable: boolField(map, 'retryable'),
    );
  }
}

final class MusePresentationSuccessReceiptV2 extends MusePresentationReceiptV2 {
  const MusePresentationSuccessReceiptV2({
    required super.receiptRef,
    required super.requestRef,
    required super.attemptRef,
    required super.completedAt,
    required super.traceRef,
    required this.result,
    required this.effectiveMode,
    required this.selectedAdapterRef,
    required this.resourceRef,
    required this.revision,
    required this.sessionRef,
    required this.surfaceInstanceRef,
    required this.warnings,
  });
  @override
  final MusePresentationResult result;
  final MuseEffectiveMode effectiveMode;
  final String selectedAdapterRef,
      resourceRef,
      revision,
      sessionRef,
      surfaceInstanceRef;
  final List<String> warnings;
  @override
  Map<String, Object?> toJson() => {
    ...baseJson(),
    'result': enumWire(result),
    'effectiveMode': enumWire(effectiveMode),
    'selectedAdapterRef': selectedAdapterRef,
    'resourceRef': resourceRef,
    'revision': revision,
    'sessionRef': sessionRef,
    'surfaceInstanceRef': surfaceInstanceRef,
    'warnings': warnings,
  };
}

final class MusePresentationFailureReceiptV2 extends MusePresentationReceiptV2 {
  const MusePresentationFailureReceiptV2({
    required super.receiptRef,
    required super.requestRef,
    required super.attemptRef,
    required super.completedAt,
    required super.traceRef,
    required this.result,
    required this.errorCode,
    required this.retryable,
  });
  @override
  final MusePresentationResult result;
  final String errorCode;
  final bool retryable;
  @override
  Map<String, Object?> toJson() => {
    ...baseJson(),
    'result': enumWire(result),
    'errorCode': errorCode,
    'retryable': retryable,
  };
}

sealed class MusePresentationWireValueV2 {
  const MusePresentationWireValueV2();
  Map<String, Object?> toJson();
  factory MusePresentationWireValueV2.fromJson(
    String kind,
    Map<String, Object?> map,
  ) => switch (kind) {
    'request' => MusePresentationRequestMessage(
      MusePresentationRequestV2.fromJson(map),
    ),
    'route-decision' => MuseRouteDecisionMessage(
      MuseRouteDecisionV2.fromJson(map),
    ),
    'receipt' => MusePresentationReceiptMessage(
      MusePresentationReceiptV2.fromJson(map),
    ),
    _ => throw MuseContractFormatException(
      'unknown presentation schema kind $kind',
    ),
  };
}

final class MusePresentationRequestMessage extends MusePresentationWireValueV2 {
  const MusePresentationRequestMessage(this.value);
  final MusePresentationRequestV2 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class MuseRouteDecisionMessage extends MusePresentationWireValueV2 {
  const MuseRouteDecisionMessage(this.value);
  final MuseRouteDecisionV2 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class MusePresentationReceiptMessage extends MusePresentationWireValueV2 {
  const MusePresentationReceiptMessage(this.value);
  final MusePresentationReceiptV2 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

void _validateReasonCodes(List<String> codes) {
  final pattern = RegExp(r'^[A-Z][A-Z0-9_]*$');
  if (codes.any((code) => !pattern.hasMatch(code)))
    throw const MuseContractFormatException(
      'reason codes must be stable upper-snake-case codes',
    );
}
