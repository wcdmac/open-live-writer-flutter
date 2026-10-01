import 'dart:collection';

/// A bounded least-recently-used map.
///
/// Insertion order doubles as recency order: reading or writing a key moves
/// it to the "most recent" end, and when the map exceeds [maxEntries] the
/// eldest (least recently used) entry is evicted automatically.
///
/// Used by [MediaCache] to track which image URLs were touched most recently
/// without letting the in-memory bookkeeping grow without bound over a long
/// session — the exact concern called out in the P1-6 audit (image metadata
/// map previously had no fixed ceiling).
class LruMap<K, V> {
  LruMap({required this.maxEntries}) : assert(maxEntries > 0);

  final int maxEntries;
  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();

  /// Number of entries currently held.
  int get length => _map.length;

  /// Whether [key] is present.
  bool containsKey(K key) => _map.containsKey(key);

  /// All keys, ordered eldest → most recent.
  Iterable<K> get keys => _map.keys;

  /// Returns the value for [key], marking it most-recently-used in the
  /// process. Returns null when absent (and does not affect recency).
  V? operator [](K key) {
    final value = _map[key];
    if (value != null) _bump(key, value);
    return value;
  }

  /// Associates [value] with [key] as most-recently-used, evicting the
  /// eldest entry if the cap is exceeded.
  void operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    if (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
  }

  /// Removes [key] if present.
  void remove(K key) => _map.remove(key);

  /// Drops all entries.
  void clear() => _map.clear();

  void _bump(K key, V value) {
    _map.remove(key);
    _map[key] = value;
  }
}
