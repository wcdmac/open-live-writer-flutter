/// Versioned envelope for the single-key JSON payloads written by
/// [AccountStore] and [LocalDraftStore].
///
/// SharedPreferences stores the whole array under one key, so adding a field
/// to the on-disk shape would otherwise make older data undecodable. Wrapping
/// it as `{schemaVersion, items}` lets future migrations read `schemaVersion`
/// and adapt instead of dropping the record. Legacy bare-array payloads
/// (schema v0) are still accepted on read.
library;

/// Current on-disk schema version for the single-key account/draft payloads.
const int kStoreSchemaVersion = 1;

/// Wraps a list of per-record JSON maps in the versioned envelope.
Map<String, dynamic> wrapStorePayload(List<Map<String, dynamic>> items) =>
    {'schemaVersion': kStoreSchemaVersion, 'items': items};

/// Unwraps a decoded payload back to its record list.
///
/// Throws [FormatException] for unrecognised shapes — callers MUST let that
/// propagate so a corrupt/mismatched payload aborts the write instead of
/// being overwritten (the strict data-loss guard from the S3 fix).
List<dynamic> unwrapStorePayload(Object? decoded) {
  if (decoded is List) {
    // Legacy v0 payload: a bare JSON array.
    return decoded;
  }
  if (decoded is Map && decoded['schemaVersion'] is int) {
    final items = decoded['items'];
    if (items is List) return items;
    throw const FormatException('store payload missing items list');
  }
  throw const FormatException('unrecognised store payload format');
}
