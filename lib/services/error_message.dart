import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Maps an arbitrary exception to a message that is safe to render in the UI.
///
/// Protocol errors (REST responses, XML-RPC faults) routinely embed the blog
/// endpoint, the account name, local filesystem paths and — for some auth
/// failures — credential material. Rendering `'$e'` verbatim leaked all of
/// that into the UI (and into any screenshot taken of it).
///
/// This classifies the failure into a stable, actionable category and routes
/// the detail to the log instead.
///
/// [context] is a short label for the log line, e.g. `'sync'`.
String userFacingError(Object error, {String context = 'error'}) {
  debugPrint('$context failed: $error');
  return _categorize(error);
}

String _categorize(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (error is SocketException ||
      error is TimeoutException ||
      lower.contains('timed out') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection closed') ||
      lower.contains('connection reset')) {
    return 'Network error: the blog could not be reached. '
        'Check your connection and try again.';
  }
  if (error is HandshakeException ||
      lower.contains('certificate') ||
      lower.contains('ssl') ||
      lower.contains('tls')) {
    return 'Secure connection failed: the site certificate could not be '
        'verified.';
  }
  if (lower.contains('401') ||
      lower.contains('unauthorized') ||
      lower.contains('403') ||
      lower.contains('forbidden')) {
    return 'The blog rejected the login. Check the account credentials, or '
        'remove and re-add the account.';
  }
  if (lower.contains('404') || lower.contains('not found')) {
    return 'The blog API endpoint was not found. Check the API URL for this '
        'account.';
  }
  if (RegExp(r'\b413\b').hasMatch(raw)) {
    return 'The server rejected the upload as too large.';
  }
  if (RegExp(r'\b5\d\d\b').hasMatch(raw)) {
    return 'The blog server returned an error. Please try again later.';
  }
  if (error is FormatException || error is FileSystemException) {
    return 'Local data could not be read or written.';
  }
  return 'Something went wrong. Please try again.';
}
