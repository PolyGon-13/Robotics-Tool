// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

void main() {
  const size = 1024;

  // ── 베이스 이미지 (파란 배경) ──────────────────────────────────────────────
  final image = img.Image(width: size, height: size);
  img.fill(image, color: img.ColorRgb8(21, 101, 192)); // #1565C0

  _drawRobot(image, opaque: false);

  final iconFile = File('assets/icon/app_icon.png');
  iconFile.createSync(recursive: true);
  iconFile.writeAsBytesSync(img.encodePng(image));
  print('Saved: ${iconFile.path}');

  // ── Foreground 이미지 (투명 배경, adaptive icon용) ────────────────────────
  final fg = img.Image(width: size, height: size, numChannels: 4);
  _drawRobot(fg, opaque: true);

  final fgFile = File('assets/icon/app_icon_foreground.png');
  fgFile.writeAsBytesSync(img.encodePng(fg));
  print('Saved: ${fgFile.path}');
}

void _drawRobot(img.Image image, {required bool opaque}) {
  img.Color c(int r, int g, int b) =>
      opaque ? img.ColorRgba8(r, g, b, 255) : img.ColorRgb8(r, g, b);

  // 얼굴 (둥근 사각형, 회색)
  _fillRoundRect(image, 212, 280, 812, 780, 80, c(176, 190, 197));

  // 눈 (파란 LED 원형)
  _fillCircle(image, 350, 460, 80, c(66, 165, 245));
  _fillCircle(image, 674, 460, 80, c(66, 165, 245));

  // 눈 반짝임 (흰색 점)
  _fillCircle(image, 370, 440, 24, c(255, 255, 255));
  _fillCircle(image, 694, 440, 24, c(255, 255, 255));

  // 입 (직사각형, 짙은 회색)
  img.fillRect(image, x1: 320, y1: 600, x2: 704, y2: 640, color: c(120, 144, 156));
  // 입 치아 구분선
  img.fillRect(image, x1: 404, y1: 600, x2: 424, y2: 640, color: c(176, 190, 197));
  img.fillRect(image, x1: 508, y1: 600, x2: 528, y2: 640, color: c(176, 190, 197));
  img.fillRect(image, x1: 612, y1: 600, x2: 632, y2: 640, color: c(176, 190, 197));

  // 안테나 (머리 위 중앙)
  img.fillRect(image, x1: 496, y1: 160, x2: 528, y2: 280, color: c(144, 164, 174));
  _fillCircle(image, 512, 136, 40, c(144, 164, 174));

  // 귀 (좌우 작은 사각형)
  img.fillRect(image, x1: 148, y1: 380, x2: 212, y2: 480, color: c(144, 164, 174));
  img.fillRect(image, x1: 812, y1: 380, x2: 876, y2: 480, color: c(144, 164, 174));
}

void _fillRoundRect(
  img.Image image,
  int x1, int y1, int x2, int y2,
  int radius,
  img.Color color,
) {
  final cx1 = x1 + radius;
  final cy1 = y1 + radius;
  final cx2 = x2 - radius;
  final cy2 = y2 - radius;

  for (int y = y1; y <= y2; y++) {
    for (int x = x1; x <= x2; x++) {
      bool inside = true;
      if (x < cx1 && y < cy1) {
        inside = _dist(x, y, cx1, cy1) <= radius;
      } else if (x > cx2 && y < cy1) {
        inside = _dist(x, y, cx2, cy1) <= radius;
      } else if (x < cx1 && y > cy2) {
        inside = _dist(x, y, cx1, cy2) <= radius;
      } else if (x > cx2 && y > cy2) {
        inside = _dist(x, y, cx2, cy2) <= radius;
      }
      if (inside) image.setPixel(x, y, color);
    }
  }
}

void _fillCircle(img.Image image, int cx, int cy, int r, img.Color color) {
  for (int y = cy - r; y <= cy + r; y++) {
    for (int x = cx - r; x <= cx + r; x++) {
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= r * r &&
          x >= 0 && x < image.width &&
          y >= 0 && y < image.height) {
        image.setPixel(x, y, color);
      }
    }
  }
}

double _dist(int px, int py, int cx, int cy) {
  final dx = px - cx;
  final dy = py - cy;
  return sqrt((dx * dx + dy * dy).toDouble());
}
