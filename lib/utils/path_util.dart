import 'dart:io' show Platform;

/// Path helpers that keep OS-account information out of anything the app
/// shows to the user or writes to logs.
///
/// Absolute export paths embed the local username (e.g.
/// `/Users/alice/Documents/...` or `C:\Users\bob\...`). Rendering or logging
/// them leaks the machine layout and account name, so the UI only ever sees
/// the file name and diagnostics get a `~`-collapsed form.
library;

/// The current user's home directory, or `null` when it cannot be resolved.
String? get _userHome {
  if (Platform.isWindows) {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) return userProfile;
    final drive = Platform.environment['HOMEDRIVE'];
    final home = Platform.environment['HOMEPATH'];
    if (drive != null && home != null && home.isNotEmpty) return '$drive$home';
    return null;
  }
  return Platform.environment['HOME'];
}

/// Collapses the user's home directory (and the account name inside it) to
/// `~`, so an absolute path can be logged or printed without leaking the
/// local username or machine layout.
///
/// Examples:
///   /Users/alice/Documents/x.md → ~/Documents/x.md
///   C:\Users\bob\Downloads\x.md → ~\Downloads\x.md
String desensitizePath(String path) {
  final sep = Platform.pathSeparator;
  final home = _userHome;
  if (home != null && home.isNotEmpty) {
    final normalizedHome = home.endsWith(sep) ? home : '$home$sep';
    if (path == home) return '~';
    if (path.startsWith(normalizedHome)) {
      return '~$sep${path.substring(normalizedHome.length)}';
    }
  }

  // Fallback for paths that don't start with the resolved home (e.g. a
  // manually mounted volume): drop any `/Users/<name>` or `C:\Users\<name>`
  // segment we can still recognise.
  final parts = path.split(sep).where((p) => p.isNotEmpty).toList();
  final userIdx = parts.indexWhere((p) => p.toUpperCase() == 'USERS');
  if (userIdx >= 0 && userIdx + 1 < parts.length) {
    final rest = parts.sublist(userIdx + 2).join(sep);
    return '~$sep$rest';
  }
  return path;
}

/// The portion of a path that is safe to render in the UI: just the file
/// name. The full path stays available for the share / copy actions.
String displayFileName(String path) {
  final sep = Platform.pathSeparator;
  final cleaned = path.endsWith(sep) ? path.substring(0, path.length - 1) : path;
  final idx = cleaned.lastIndexOf(sep);
  return idx >= 0 ? cleaned.substring(idx + 1) : cleaned;
}
