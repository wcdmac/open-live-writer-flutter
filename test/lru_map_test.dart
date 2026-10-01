import 'package:flutter_test/flutter_test.dart';
import 'package:open_live_writer/utils/lru_map.dart';

void main() {
  test('evicts the least-recently-used entry when the cap is exceeded', () {
    final lru = LruMap<String, int>(maxEntries: 3);
    lru['a'] = 1;
    lru['b'] = 2;
    lru['c'] = 3;
    // All three present.
    expect(lru.length, 3);
    // Adding a fourth evicts the eldest ('a').
    lru['d'] = 4;
    expect(lru.length, 3);
    expect(lru.containsKey('a'), isFalse);
    expect(lru.containsKey('b'), isTrue);
    expect(lru.containsKey('c'), isTrue);
    expect(lru.containsKey('d'), isTrue);
  });

  test('reading a key makes it most-recently-used', () {
    final lru = LruMap<String, int>(maxEntries: 2);
    lru['a'] = 1;
    lru['b'] = 2;
    // Touch 'a' so it becomes most recent; 'b' is now eldest.
    expect(lru['a'], 1);
    lru['c'] = 3; // should evict 'b', not 'a'
    expect(lru.containsKey('a'), isTrue);
    expect(lru.containsKey('b'), isFalse);
    expect(lru.containsKey('c'), isTrue);
  });

  test('re-assigning a key keeps it (no duplicate), most-recent', () {
    final lru = LruMap<String, int>(maxEntries: 2);
    lru['a'] = 1;
    lru['b'] = 2;
    lru['a'] = 10; // reassign, stays, still most recent
    expect(lru.length, 2);
    expect(lru['a'], 10);
    lru['c'] = 3; // evicts 'b'
    expect(lru.containsKey('b'), isFalse);
    expect(lru.containsKey('a'), isTrue);
  });

  test('keys are ordered eldest to most-recent', () {
    final lru = LruMap<String, int>(maxEntries: 4);
    lru['a'] = 1;
    lru['b'] = 2;
    lru['c'] = 3;
    // Reading 'a' moves it to the end.
    lru['a'];
    expect(lru.keys.toList(), ['b', 'c', 'a']);
  });

  test('remove and clear drop entries', () {
    final lru = LruMap<String, int>(maxEntries: 3);
    lru['a'] = 1;
    lru['b'] = 2;
    lru.remove('a');
    expect(lru.containsKey('a'), isFalse);
    lru.clear();
    expect(lru.length, 0);
  });

  test('absent key returns null and does not affect recency', () {
    final lru = LruMap<String, int>(maxEntries: 2);
    lru['a'] = 1;
    expect(lru['missing'], isNull);
    expect(lru.length, 1);
  });
}
