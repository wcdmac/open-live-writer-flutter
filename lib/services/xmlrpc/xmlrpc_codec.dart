import 'dart:convert';

import 'package:xml/xml.dart';

/// Exception thrown when the server returns an XML-RPC `<fault>` response.
class XmlRpcFault implements Exception {
  XmlRpcFault(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'XML-RPC fault $code: $message';
}

/// Encodes Dart values into XML-RPC `<param>` fragments and decodes
/// `<value>` nodes back into Dart values.
///
/// Dart -> XML-RPC mapping:
///   null              -> `string`
///   int               -> `int`
///   double            -> `double`
///   bool              -> `boolean`
///   String            -> `string`
///   DateTime          -> `dateTime.iso8601`
///   List              -> `array`
///   Map String to _   -> `struct`
class XmlRpcCodec {
  /// Builds a complete XML-RPC request document.
  static String encodeRequest(String methodName, List<dynamic> params) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0"');
    builder.element('methodCall', nest: () {
      builder.element('methodName', nest: methodName);
      if (params.isNotEmpty) {
        builder.element('params', nest: () {
          for (final param in params) {
            builder.element('param',
                nest: () => builder.element('value',
                    nest: () => _encodeValue(builder, param)));
          }
        });
      }
    });
    return builder.buildDocument().toXmlString(pretty: false);
  }

  static void _encodeValue(XmlBuilder b, dynamic value) {
    if (value == null) {
      b.element('string', nest: '');
    } else if (value is bool) {
      b.element('boolean', nest: value ? '1' : '0');
    } else if (value is int) {
      b.element('int', nest: value.toString());
    } else if (value is double) {
      b.element('double', nest: value.toString());
    } else if (value is DateTime) {
      b.element('dateTime.iso8601', nest: _encodeDateTime(value));
    } else if (value is List<int>) {
      // Binary payload (media upload bits) — XML-RPC base64, NOT an
      // int array: encoding 260k bytes as <int> nodes produces an ~8MB
      // document that servers reject with parse errors / 413.
      b.element('base64', nest: base64Encode(value));
    } else if (value is List) {
      b.element('array', nest: () {
        b.element('data', nest: () {
          for (final item in value) {
            b.element('value', nest: () => _encodeValue(b, item));
          }
        });
      });
    } else if (value is Map) {
      b.element('struct', nest: () {
        value.forEach((key, val) {
          b.element('member', nest: () {
            b.element('name', nest: key.toString());
            b.element('value', nest: () => _encodeValue(b, val));
          });
        });
      });
    } else {
      b.element('string', nest: value.toString());
    }
  }

  /// XML-RPC dateTime format: 19980717T14:08:55 (+ optional TZ offset).
  static String _encodeDateTime(DateTime dt) {
    final utc = dt.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
        '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  }

  /// Parses an XML-RPC response document into the returned Dart value.
  static dynamic decodeResponse(String body) {
    final doc = XmlDocument.parse(body);
    final methodResponse = doc.rootElement;
    if (methodResponse.name.local != 'methodResponse') {
      throw XmlRpcFault(-32700, 'Invalid XML-RPC response root element');
    }

    final fault = methodResponse.findElements('fault').firstOrNull;
    if (fault != null) {
      final faultValue = fault.findElements('value').firstOrNull;
      final faultData =
          faultValue == null ? null : _decodeValue(faultValue);
      if (faultData is Map) {
        final code = int.tryParse('${faultData['faultCode']}') ?? 0;
        final message = '${faultData['faultString']}';
        throw XmlRpcFault(code, message);
      }
      throw XmlRpcFault(-32603, 'Unknown XML-RPC fault');
    }

    final param = methodResponse
            .findElements('params')
            .firstOrNull
            ?.findElements('param')
            .firstOrNull ??
        (throw XmlRpcFault(-32603, 'Empty XML-RPC response (no params)'));

    final value = param.findElements('value').firstOrNull;
    if (value == null) return null;
    return _decodeValue(value);
  }

  static dynamic _decodeValue(XmlElement value) {
    // A <value> may contain text directly (implicit string) or a typed child.
    for (final child in value.childElements) {
      switch (child.name.local) {
        case 'int' || 'i4':
          return int.tryParse(child.innerText.trim());
        case 'i8':
          return int.tryParse(child.innerText.trim());
        case 'boolean':
          return child.innerText.trim() == '1';
        case 'double':
          return double.tryParse(child.innerText.trim());
        case 'dateTime.iso8601':
          return _decodeDateTime(child.innerText.trim());
        case 'base64':
          return base64Decode(child.innerText.trim());
        case 'string':
          return child.innerText;
        case 'array':
          return child
              .findElements('data')
              .firstOrNull
              ?.findElements('value')
              .map(_decodeValue)
              .toList() ??
              <dynamic>[];
        case 'struct':
          final map = <String, dynamic>{};
          for (final member in child.findElements('member')) {
            final name =
                member.findElements('name').firstOrNull?.innerText ?? '';
            final memberValue = member.findElements('value').firstOrNull;
            map[name] =
                memberValue == null ? null : _decodeValue(memberValue);
          }
          return map;
      }
    }
    // Implicit string value: <value>text</value>
    return value.innerText;
  }

  /// Parses formats like `19980717T14:08:55`, `19980717T14:08:55Z`
  /// or `19980717T14:08:55+0200`. Returns null when malformed.
  static DateTime? _decodeDateTime(String raw) {
    final m = RegExp(
            r'^(\d{4})(\d{2})(\d{2})T(\d{2}):(\d{2}):(\d{2})(Z|[+-]\d{2}:?\d{2})?$')
        .firstMatch(raw);
    if (m == null) {
      // Some servers send ISO 8601 with dashes/colons.
      return DateTime.tryParse(raw);
    }
    var dt = DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
    final tz = m.group(7);
    if (tz != null && tz != 'Z') {
      final sign = tz.startsWith('-') ? -1 : 1;
      final digits = tz.substring(1).replaceAll(':', '');
      final hours = int.parse(digits.substring(0, 2));
      final minutes = int.parse(digits.substring(2, 4));
      dt = dt.subtract(Duration(hours: hours, minutes: minutes) * sign);
    }
    return dt.toLocal();
  }
}
