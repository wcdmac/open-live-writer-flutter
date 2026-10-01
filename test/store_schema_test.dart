import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_live_writer/services/local_draft_store.dart';
import 'package:open_live_writer/utils/persistence_codec.dart';

LocalDraft _draft(String id) => LocalDraft(
      id: id,
      accountId: 'acct',
      title: 'title-$id',
      content: 'content-$id',
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('persistence_codec (P0-2 versioned envelope)', () {
    test('round-trips the versioned envelope', () {
      final wrapped = wrapStorePayload([
        {'id': 'a'}
      ]);
      expect(wrapped['schemaVersion'], 1);
      expect(unwrapStorePayload(jsonDecode(jsonEncode(wrapped))), isA<List>());
    });
    test('accepts legacy v0 bare arrays', () {
      expect(unwrapStorePayload([
        {'id': 'a'}
      ]), isA<List>());
    });
    test('throws FormatException on unrecognised shapes', () {
      expect(() => unwrapStorePayload({'foo': 'bar'}),
          throwsA(isA<FormatException>()));
      expect(() => unwrapStorePayload(42), throwsA(isA<FormatException>()));
    });
  });

  group('LocalDraftStore schema (P0-2)', () {
    test('writes the versioned envelope and reads it back', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalDraftStore();
      await store.saveDraft(_draft('a'));

      final raw =
          (await SharedPreferences.getInstance()).getString('olw.drafts.acct')!;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 1);
      expect(decoded['items'], isA<List>());

      final drafts = await store.loadDrafts('acct');
      expect(drafts.map((d) => d.id), ['a']);
    });

    test('legacy v0 bare-array payload still loads', () async {
      SharedPreferences.setMockInitialValues({
        'olw.drafts.acct': '[{"id":"legacy"}]'
      });
      final store = LocalDraftStore();
      final drafts = await store.loadDrafts('acct');
      expect(drafts.map((d) => d.id), ['legacy']);
    });
  });
}
