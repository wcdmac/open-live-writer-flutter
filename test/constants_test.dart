import 'package:flutter_test/flutter_test.dart';

import 'package:open_live_writer/utils/constants.dart';

void main() {
  test('editor constants hold their intended values (L1)', () {
    expect(kImageUploadQuality, 90);
    expect(kImageMaxWidth, 2560);
    expect(kHistoryDebounce, const Duration(milliseconds: 700));
    expect(kHistoryStackLimit, 100);
    expect(kWideLayoutBreakpoint, 1000);
  });
}
