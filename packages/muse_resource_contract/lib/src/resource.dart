import 'wire.dart';

enum MuseFormatConfidence { claimed, sniffed, verified }

enum MuseResourceCapability {
  describe,
  snapshot,
  materialize,
  commit,
  subscribe,
}

enum MuseSecurityClassification { public, internal, confidential, restricted }

enum MuseActiveContent { none, unknown, present, blocked }

enum MuseMaterializationKind {
  bytesHandle,
  readFileHandle,
  workingCopy,
  loopbackUrl,
  remoteUrl,
  streamHandle,
}

enum MuseAccessMode { read, readWrite }

final class MuseResourceFormat {
  const MuseResourceFormat({required this.formatId, required this.confidence});
  final String formatId;
  final MuseFormatConfidence confidence;
  factory MuseResourceFormat.fromJson(Object? value) {
    final map = objectMap(value, 'format');
    requireKeys(map, required: {'formatId', 'confidence'});
    return MuseResourceFormat(
      formatId: stringField(map, 'formatId'),
      confidence: enumField(map, 'confidence', MuseFormatConfidence.values),
    );
  }
  Map<String, Object?> toJson() => {
    'formatId': formatId,
    'confidence': enumWire(confidence),
  };
}

final class MuseResourceSecurity {
  const MuseResourceSecurity({
    required this.classification,
    required this.activeContent,
  });
  final MuseSecurityClassification classification;
  final MuseActiveContent activeContent;
  factory MuseResourceSecurity.fromJson(Object? value) {
    final map = objectMap(value, 'security');
    requireKeys(map, required: {'classification', 'activeContent'});
    return MuseResourceSecurity(
      classification: enumField(
        map,
        'classification',
        MuseSecurityClassification.values,
      ),
      activeContent: enumField(map, 'activeContent', MuseActiveContent.values),
    );
  }
  Map<String, Object?> toJson() => {
    'classification': enumWire(classification),
    'activeContent': enumWire(activeContent),
  };
}

final class MuseResourceDescriptorV1 {
  const MuseResourceDescriptorV1({
    required this.resourceRef,
    required this.revision,
    required this.displayName,
    required this.mediaType,
    required this.format,
    required this.capabilities,
    required this.security,
    this.sizeBytes,
    this.extensions,
  });
  final String resourceRef;
  final String revision;
  final String displayName;
  final String mediaType;
  final int? sizeBytes;
  final MuseResourceFormat format;
  final List<MuseResourceCapability> capabilities;
  final MuseResourceSecurity security;
  final Map<String, Object?>? extensions;

  factory MuseResourceDescriptorV1.fromJson(Map<String, Object?> map) {
    requireProtocol(map, 'muse.resource/descriptor/v1');
    requireKeys(
      map,
      required: {
        'protocol',
        'resourceRef',
        'revision',
        'displayName',
        'mediaType',
        'format',
        'capabilities',
        'security',
      },
      optional: {'sizeBytes', 'extensions'},
    );
    final extensions = map['extensions'] == null
        ? null
        : objectMap(map['extensions'], 'extensions');
    return MuseResourceDescriptorV1(
      resourceRef: stringField(map, 'resourceRef'),
      revision: stringField(map, 'revision'),
      displayName: stringField(map, 'displayName'),
      mediaType: stringField(map, 'mediaType'),
      sizeBytes: optionalInt(map, 'sizeBytes'),
      format: MuseResourceFormat.fromJson(map['format']),
      capabilities: enumList(
        map,
        'capabilities',
        MuseResourceCapability.values,
      ),
      security: MuseResourceSecurity.fromJson(map['security']),
      extensions: extensions == null ? null : deepCopyMap(extensions),
    );
  }

  Map<String, Object?> toJson() => {
    'protocol': 'muse.resource/descriptor/v1',
    'resourceRef': resourceRef,
    'revision': revision,
    'displayName': displayName,
    'mediaType': mediaType,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    'format': format.toJson(),
    'capabilities': capabilities.map(enumWire).toList(),
    'security': security.toJson(),
    if (extensions != null) 'extensions': deepCopyMap(extensions!),
  };
}

final class MuseResourceMaterializationV1 {
  const MuseResourceMaterializationV1({
    required this.handleRef,
    required this.resourceRef,
    required this.revision,
    required this.consumerAdapterRef,
    required this.kind,
    required this.accessMode,
    required this.expiresAt,
    this.sizeBytes,
    this.digest,
  });
  final String handleRef, resourceRef, revision, consumerAdapterRef;
  final MuseMaterializationKind kind;
  final MuseAccessMode accessMode;
  final int expiresAt;
  final int? sizeBytes;
  final String? digest;

  factory MuseResourceMaterializationV1.fromJson(Map<String, Object?> map) {
    requireProtocol(map, 'muse.resource/materialization/v1');
    requireKeys(
      map,
      required: {
        'protocol',
        'handleRef',
        'resourceRef',
        'revision',
        'consumerAdapterRef',
        'kind',
        'accessMode',
        'expiresAt',
      },
      optional: {'sizeBytes', 'digest'},
    );
    final kind = enumField(map, 'kind', MuseMaterializationKind.values);
    final mode = enumField(map, 'accessMode', MuseAccessMode.values);
    if ((kind == MuseMaterializationKind.remoteUrl ||
            kind == MuseMaterializationKind.loopbackUrl) &&
        mode != MuseAccessMode.read) {
      throw const MuseContractFormatException(
        'URL materializations must be read-only',
      );
    }
    return MuseResourceMaterializationV1(
      handleRef: stringField(map, 'handleRef'),
      resourceRef: stringField(map, 'resourceRef'),
      revision: stringField(map, 'revision'),
      consumerAdapterRef: stringField(map, 'consumerAdapterRef'),
      kind: kind,
      accessMode: mode,
      expiresAt: intField(map, 'expiresAt', min: 1),
      sizeBytes: optionalInt(map, 'sizeBytes'),
      digest: optionalString(map, 'digest'),
    );
  }
  Map<String, Object?> toJson() => {
    'protocol': 'muse.resource/materialization/v1',
    'handleRef': handleRef,
    'resourceRef': resourceRef,
    'revision': revision,
    'consumerAdapterRef': consumerAdapterRef,
    'kind': enumWire(kind),
    'accessMode': enumWire(accessMode),
    'expiresAt': expiresAt,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    if (digest != null) 'digest': digest,
  };
}

sealed class MuseResourceWireValueV1 {
  const MuseResourceWireValueV1();
  Map<String, Object?> toJson();

  factory MuseResourceWireValueV1.fromJson(
    String kind,
    Map<String, Object?> map,
  ) => switch (kind) {
    'descriptor' => MuseResourceDescriptorMessage(
      MuseResourceDescriptorV1.fromJson(map),
    ),
    'materialization' => MuseResourceMaterializationMessage(
      MuseResourceMaterializationV1.fromJson(map),
    ),
    'commit-request' => MuseResourceOpaqueMessage.parse(
      kind,
      'muse.resource/commit-request/v1',
      map,
    ),
    'commit-receipt' => MuseResourceOpaqueMessage.parse(
      kind,
      'muse.resource/commit-receipt/v1',
      map,
    ),
    'event' => MuseResourceOpaqueMessage.parse(
      kind,
      'muse.resource/event/v1',
      map,
    ),
    _ => throw MuseContractFormatException(
      'unknown resource schema kind $kind',
    ),
  };
}

final class MuseResourceDescriptorMessage extends MuseResourceWireValueV1 {
  const MuseResourceDescriptorMessage(this.value);
  final MuseResourceDescriptorV1 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class MuseResourceMaterializationMessage extends MuseResourceWireValueV1 {
  const MuseResourceMaterializationMessage(this.value);
  final MuseResourceMaterializationV1 value;
  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class MuseResourceOpaqueMessage extends MuseResourceWireValueV1 {
  MuseResourceOpaqueMessage._(this.kind, this._value);
  final String kind;
  final Map<String, Object?> _value;
  static MuseResourceOpaqueMessage parse(
    String kind,
    String protocol,
    Map<String, Object?> map,
  ) {
    requireProtocol(map, protocol);
    final required = switch (kind) {
      'commit-request' => {
        'protocol',
        'commitRef',
        'resourceRef',
        'expectedRevision',
        'sessionRef',
        'content',
        'intent',
        'idempotencyKey',
      },
      'event' => {
        'protocol',
        'eventRef',
        'cursor',
        'resourceRef',
        'occurredAt',
        'origin',
        'kind',
      },
      _ => {'protocol', 'result', 'commitRef', 'resourceRef'},
    };
    final optional = switch (kind) {
      'commit-receipt' => {
        'newRevision',
        'providerReceiptRef',
        'currentRevision',
        'compareRef',
        'errorCode',
      },
      'event' => {
        'beforeRevision',
        'afterRevision',
        'commandRef',
        'revision',
        'previousDisplayName',
        'displayName',
      },
      _ => const <String>{},
    };
    requireKeys(map, required: required, optional: optional);
    for (final field in required.difference({
      'protocol',
      'content',
      'occurredAt',
    })) {
      stringField(map, field);
    }
    if (kind == 'commit-request') {
      final content = objectMap(map['content'], 'content');
      requireKeys(content, required: {'kind', 'handleRef', 'digest'});
      if (!{
        'bytes-handle',
        'working-copy',
      }.contains(stringField(content, 'kind')))
        throw const MuseContractFormatException(
          'unsupported commit content kind',
        );
    }
    if (kind == 'commit-receipt') {
      final result = stringField(map, 'result');
      if ({'committed', 'no-change'}.contains(result)) {
        stringField(map, 'newRevision');
        stringField(map, 'providerReceiptRef');
      } else if (result == 'conflict') {
        stringField(map, 'currentRevision');
      } else if (!{
        'denied',
        'unsupported',
        'cancelled',
        'failed',
      }.contains(result)) {
        throw const MuseContractFormatException('unsupported commit result');
      }
    }
    if (kind == 'event') intField(map, 'occurredAt');
    return MuseResourceOpaqueMessage._(kind, deepCopyMap(map));
  }

  @override
  Map<String, Object?> toJson() => deepCopyMap(_value);
}
