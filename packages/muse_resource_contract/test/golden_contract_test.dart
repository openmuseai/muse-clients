import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_resource_contract/muse_resource_contract.dart';

void main() {
  group('authoritative wire fixtures', () {
    _fixtureSuite(
      '../../contracts/muse/contract-resource/v1/messages.json',
      MuseResourceWireValueV1.fromJson,
    );
    _fixtureSuite(
      '../../contracts/muse/contract-presentation/v2/messages.json',
      MusePresentationWireValueV2.fromJson,
    );
    _fixtureSuite(
      '../../contracts/muse/contract-engine-session/v1/messages.json',
      MuseEngineSessionWireValueV1.fromJson,
    );
  });

  test('schema digests remain pinned to the F0 contract freeze', () async {
    final expected = <String, Map<String, String>>{
      'resource': {
        'resource-descriptor':
            'sha256:237a230cd2fee2c4093d75bc1f374d3b018cbbc167079e08d3036e9c3ba3efb8',
        'materialization':
            'sha256:50a99621c89caf1c32a2efc01ba6700f1e6d195afcd4e7b2b7b311ceefa7d773',
      },
      'presentation': {
        'presentation-request':
            'sha256:275af040c9cc6d58513d82772eda8dec5ead38d0923e1ba25c32047ad77595ba',
        'presentation-receipt':
            'sha256:cfd6b830350783d673559c0cd957a658b0759231139def9a90bdc09fa79e6427',
      },
      'engine-session': {
        'adapter-manifest':
            'sha256:ff4f512fdb1e629166c0446d791f3ecd510ec3ddaa2af2e618d24abcb42b7e29',
        'session-handle':
            'sha256:2ea3176886e9c7b1fc2c4033ac971294d4935340138666e4e5e252c95dd53c85',
      },
    };
    for (final entry in expected.entries) {
      final version = entry.key == 'presentation' ? 'v2' : 'v1';
      final path =
          '../../contracts/muse/contract-${entry.key}/$version/schema-digests.json';
      final actual = (jsonDecode(await File(path).readAsString()) as Map)
          .cast<String, Object?>();
      for (final digest in entry.value.entries) {
        expect(actual[digest.key], digest.value, reason: '$path:${digest.key}');
      }
    }
  });
}

typedef _Parser = Object Function(String kind, Map<String, Object?> value);

void _fixtureSuite(String path, _Parser parser) {
  test('round-trips valid and rejects invalid: $path', () async {
    final fixtures = (jsonDecode(await File(path).readAsString()) as List)
        .cast<Map>();
    for (final raw in fixtures) {
      final fixture = raw.cast<String, Object?>();
      final kind = fixture['kind']! as String;
      final value = (fixture['value']! as Map).cast<String, Object?>();
      if (fixture['valid'] == true) {
        final parsed = parser(kind, value) as dynamic;
        expect(parsed.toJson(), value, reason: fixture['name']! as String);
      } else {
        expect(
          () => parser(kind, value),
          throwsA(isA<FormatException>()),
          reason: fixture['name']! as String,
        );
      }
    }
  });
}
