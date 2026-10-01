import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_live_writer/services/local_draft_store.dart';

LocalDraft _draft(String id) => LocalDraft(
      id: id,
      accountId: 'acct',
      title: 'title-$id',
      content: 'content-$id',
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalDraftStore data-loss guard (S3)', () {
    test('saveDraft refuses to overwrite a corrupt payload', () async {
      SharedPreferences.setMockInitialValues({'olw.drafts.acct': '{not json'});
      final store = LocalDraftStore();

      // Must abort rather than treat the payload as "no drafts" and write a
      // list containing only the new draft — which destroyed every other one.
      await expectLater(
        store.saveDraft(_draft('a')),
        throwsA(isA<FormatException>()),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('olw.drafts.acct'), '{not json');
    });

    test('a single malformed entry no longer drops the whole list', () async {
      SharedPreferences.setMockInitialValues({
        'olw.drafts.acct':
            '[{"id":"good"},"i am not an object",{"id":""},42]',
      });
      final store = LocalDraftStore();

      final drafts = await store.loadDrafts('acct');
      // The unusable entries are skipped; the valid one survives.
      expect(drafts.map((d) => d.id), ['good']);
    });

    test('normal save/load round-trips unchanged', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalDraftStore();

      await store.saveDraft(_draft('a'));
      await store.saveDraft(_draft('b'));

      final drafts = await store.loadDrafts('acct');
      expect(drafts.map((d) => d.id).toList()..sort(), ['a', 'b']);
    });

    test('deleteDraft also refuses to rewrite a corrupt payload', () async {
      SharedPreferences.setMockInitialValues({'olw.drafts.acct': '[]]'});
      final store = LocalDraftStore();

      await expectLater(
        store.deleteDraft('acct', 'a'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
