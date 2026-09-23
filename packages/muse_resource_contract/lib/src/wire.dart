typedef MuseJsonValue = Object?;

final class MuseContractFormatException implements FormatException {
  const MuseContractFormatException(this.message, [this.source, this.offset]);

  @override
  final String message;
  @override
  final Object? source;
  @override
  final int? offset;

  @override
  String toString() => 'MuseContractFormatException: $message';
}

Map<String, Object?> objectMap(Object? value, String field) {
  if (value is! Map)
    throw MuseContractFormatException('$field must be an object');
  try {
    return value.cast<String, Object?>();
  } on TypeError {
    throw MuseContractFormatException('$field must use string keys');
  }
}

List<Object?> objectList(Object? value, String field) {
  if (value is! List)
    throw MuseContractFormatException('$field must be an array');
  return value.cast<Object?>();
}

String stringField(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! String || value.isEmpty) {
    throw MuseContractFormatException('$field must be a non-empty string');
  }
  return value;
}

int intField(Map<String, Object?> map, String field, {int min = 0}) {
  final value = map[field];
  if (value is! int || value < min) {
    throw MuseContractFormatException('$field must be an integer >= $min');
  }
  return value;
}

bool boolField(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! bool)
    throw MuseContractFormatException('$field must be a boolean');
  return value;
}

String? optionalString(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw MuseContractFormatException('$field must be a non-empty string');
  }
  return value;
}

int? optionalInt(Map<String, Object?> map, String field, {int min = 0}) {
  final value = map[field];
  if (value == null) return null;
  if (value is! int || value < min) {
    throw MuseContractFormatException('$field must be an integer >= $min');
  }
  return value;
}

T enumField<T extends Enum>(
  Map<String, Object?> map,
  String field,
  List<T> values,
) {
  final raw = stringField(map, field);
  return values.where((value) => enumWire(value) == raw).firstOrNull ??
      (throw MuseContractFormatException('$field has unsupported value $raw'));
}

List<T> enumList<T extends Enum>(
  Map<String, Object?> map,
  String field,
  List<T> values, {
  bool unique = true,
}) {
  final result = objectList(map[field], field)
      .map((raw) {
        if (raw is! String)
          throw MuseContractFormatException('$field must contain strings');
        return values.where((value) => enumWire(value) == raw).firstOrNull ??
            (throw MuseContractFormatException(
              '$field has unsupported value $raw',
            ));
      })
      .toList(growable: false);
  if (unique && result.toSet().length != result.length) {
    throw MuseContractFormatException('$field must contain unique values');
  }
  return result;
}

List<String> stringList(
  Map<String, Object?> map,
  String field, {
  bool unique = true,
}) {
  final result = objectList(map[field], field)
      .map((value) {
        if (value is! String || value.isEmpty) {
          throw MuseContractFormatException(
            '$field must contain non-empty strings',
          );
        }
        return value;
      })
      .toList(growable: false);
  if (unique && result.toSet().length != result.length) {
    throw MuseContractFormatException('$field must contain unique values');
  }
  return result;
}

String enumWire(Enum value) => value.name.replaceAllMapped(
  RegExp(r'(?<=[a-z0-9])([A-Z])'),
  (match) => '-${match.group(1)!.toLowerCase()}',
);

void requireProtocol(Map<String, Object?> map, String protocol) {
  if (map['protocol'] != protocol) {
    throw MuseContractFormatException('protocol must be $protocol');
  }
}

void requireKeys(
  Map<String, Object?> map, {
  required Set<String> required,
  Set<String> optional = const {},
}) {
  final missing = required.difference(map.keys.toSet());
  if (missing.isNotEmpty) {
    throw MuseContractFormatException('missing fields: ${missing.join(', ')}');
  }
  final unknown = map.keys.toSet().difference(required.union(optional));
  if (unknown.isNotEmpty) {
    throw MuseContractFormatException('unknown fields: ${unknown.join(', ')}');
  }
}

Map<String, Object?> deepCopyMap(Map<String, Object?> value) =>
    value.map((key, item) => MapEntry(key, deepCopy(item)));

Object? deepCopy(Object? value) => switch (value) {
  Map() => deepCopyMap(value.cast<String, Object?>()),
  List() => value.map(deepCopy).toList(growable: false),
  _ => value,
};
