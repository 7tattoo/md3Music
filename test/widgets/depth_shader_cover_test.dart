import 'package:flutter_test/flutter_test.dart';
import 'package:md3music/widgets/depth_shader_cover.dart';

void main() {
  group('shiftScaleFor（ShengChao strengthScale 对齐）', () {
    test('层次丰富（std=0.18）→ 1.0', () {
      expect(DepthShaderCover.shiftScaleFor(0.18), closeTo(1.0, 1e-6));
    });
    test('层次平（std=0.09）→ 放大到 2.0', () {
      expect(DepthShaderCover.shiftScaleFor(0.09), closeTo(2.0, 1e-6));
    });
    test('极平（std=0.05）→ 上限 2.5；极丰富（std=0.3）→ 下限 0.6', () {
      expect(DepthShaderCover.shiftScaleFor(0.05), closeTo(2.5, 1e-6));
      expect(DepthShaderCover.shiftScaleFor(0.3), closeTo(0.6, 1e-6));
    });
    test('std=0（异常兜底）→ 1.0', () {
      expect(DepthShaderCover.shiftScaleFor(0.0), 1.0);
    });
  });
}
