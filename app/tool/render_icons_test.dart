// Renders Chatter's launcher icons for every platform from BrandMarkPainter,
// so the app's mark and its icons stay identical. Not part of the test suite;
// run it after changing the mark:
//
//   flutter test tool/render_icons_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Night ink: the icon tile behind the amber bubble.
const slate = AppTheme.night;

typedef Draw = void Function(Canvas canvas, double size);

Future<ui.Image> render(int px, Draw draw) {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder), px.toDouble());
  return recorder.endRecording().toImage(px, px);
}

/// The mark centred at [scale] of the canvas; heavier strokes at small sizes.
void mark(Canvas c, double s, double scale, {bool knockout = false, Color? bubble}) {
  final m = s * scale;
  c.save();
  c.translate((s - m) / 2, (s - m) / 2);
  BrandMarkPainter(
    knockout: knockout,
    small: m <= 40,
    bubble: bubble ?? const BrandMarkPainter().bubble,
  ).paint(c, Size.square(m));
  c.restore();
}

/// A slate tile (full-bleed, or rounded and inset) with the mark on it.
Draw tile({double inset = 0, double radius = 0, required double markScale}) => (c, s) {
      final side = s * (1 - 2 * inset);
      final rect = Rect.fromLTWH(s * inset, s * inset, side, side);
      c.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(side * radius)), Paint()..color = slate);
      mark(c, s, markScale);
    };

Future<Uint8List> pngRgba(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

/// PNG without an alpha channel: App Store icons are rejected if they have one.
Future<Uint8List> pngRgb(ui.Image image) async {
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final w = image.width, h = image.height;
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      raw.add([rgba[i], rgba[i + 1], rgba[i + 2]]);
    }
  }
  final out = BytesBuilder()..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    out
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc32(body)));
  }

  chunk('IHDR', [..._u32(w), ..._u32(h), 8, 2, 0, 0, 0]); // 8-bit RGB
  chunk('IDAT', ZLibEncoder().convert(raw.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// Windows .ico holding PNG images, one per size.
Uint8List ico(List<(int, Uint8List)> images) {
  final out = BytesBuilder();
  List<int> u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  List<int> u32le(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  out
    ..add(u16(0))
    ..add(u16(1))
    ..add(u16(images.length));
  var offset = 6 + 16 * images.length;
  for (final (size, png) in images) {
    out
      ..add([size >= 256 ? 0 : size, size >= 256 ? 0 : size, 0, 0])
      ..add(u16(1))
      ..add(u16(32))
      ..add(u32le(png.length))
      ..add(u32le(offset));
    offset += png.length;
  }
  for (final (_, png) in images) {
    out.add(png);
  }
  return out.takeBytes();
}

void write(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

void main() {
  testWidgets('render launcher icons', (tester) async {
    await tester.runAsync(() async {
      // Android: legacy icons, plus adaptive foreground and themed-icon layers
      // on a 108dp canvas whose safe zone is the central 66dp circle
      const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
      const res = 'android/app/src/main/res';
      for (final MapEntry(key: d, value: f) in densities.entries) {
        write('$res/mipmap-$d/ic_launcher.png',
            await pngRgba(await render((48 * f).round(), tile(inset: 0.04, radius: 0.22, markScale: 0.66))));
        write('$res/mipmap-$d/ic_launcher_foreground.png',
            await pngRgba(await render((108 * f).round(), (c, s) => mark(c, s, 0.56))));
        write('$res/mipmap-$d/ic_launcher_monochrome.png',
            await pngRgba(await render((108 * f).round(), (c, s) => mark(c, s, 0.56, knockout: true, bubble: Colors.white))));
      }

      // iOS: opaque, full-bleed squares; the system rounds the corners
      const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      const iosIcons = {
        'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167, 'Icon-App-1024x1024@1x.png': 1024,
      };
      for (final MapEntry(key: name, value: px) in iosIcons.entries) {
        write('$ios/$name', await pngRgb(await render(px, tile(markScale: 0.68))));
      }

      // macOS: the standard rounded tile inset on a transparent canvas
      for (final px in [16, 32, 64, 128, 256, 512, 1024]) {
        write('macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$px.png',
            await pngRgba(await render(px, tile(inset: 0.098, radius: 0.225, markScale: 0.56))));
      }

      // Web: rounded icons, maskable ones with the mark inside the safe zone
      for (final px in [192, 512]) {
        write('web/icons/Icon-$px.png', await pngRgba(await render(px, tile(radius: 0.22, markScale: 0.68))));
        write('web/icons/Icon-maskable-$px.png', await pngRgba(await render(px, tile(markScale: 0.56))));
      }
      write('web/favicon.png', await pngRgba(await render(32, tile(radius: 0.2, markScale: 0.84))));

      // Windows
      final winSizes = [16, 24, 32, 48, 64, 256];
      write('windows/runner/resources/app_icon.ico', ico([
        for (final px in winSizes)
          (px, await pngRgba(await render(px, tile(radius: 0.2, markScale: px <= 32 ? 0.84 : 0.72)))),
      ]));
    });
  });
}
