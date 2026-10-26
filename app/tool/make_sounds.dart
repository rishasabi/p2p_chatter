// Writes the alert sounds in assets/sounds/. They're synthesised here, not
// recorded or downloaded, so Chatter owns them outright and they can be
// tuned and rebuilt: dart run tool/make_sounds.dart
//
// 16-bit mono PCM WAV at 22.05 kHz: tiny, and played as is by Android's
// SoundPool with no decoding step.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const rate = 22050;

/// A tone of [hz] (and a softer octave above, for body) starting at [start]
/// seconds, struck and fading over [length].
void tone(List<double> out, double start, double length, double hz, double volume, {double decay = 6}) {
  final from = (start * rate).round();
  final n = (length * rate).round();
  for (var i = 0; i < n && from + i < out.length; i++) {
    final t = i / rate;
    final attack = math.min(1.0, t / 0.005); // no click at the start
    final envelope = attack * math.exp(-decay * t);
    final wave = math.sin(2 * math.pi * hz * t) + 0.25 * math.sin(4 * math.pi * hz * t);
    out[from + i] += volume * envelope * wave / 1.25;
  }
}

/// A siren: [sweeps] rises and falls between [low] and [high] Hz.
void siren(List<double> out, double start, double sweep, int sweeps, double low, double high, double volume) {
  final from = (start * rate).round();
  final n = (sweep * sweeps * rate).round();
  var phase = 0.0;
  for (var i = 0; i < n && from + i < out.length; i++) {
    final t = i / rate;
    final position = (t % sweep) / sweep; // 0..1 within one sweep
    final hz = low + (high - low) * (1 - (2 * position - 1).abs());
    phase += 2 * math.pi * hz / rate;
    final edge = math.min(1.0, math.min(t, sweep * sweeps - t) / 0.01);
    // A little odd harmonic so it cuts through crowd noise
    final wave = math.sin(phase) + 0.3 * math.sin(3 * phase);
    out[from + i] += volume * edge * wave / 1.3;
  }
}

void write(String name, List<double> samples) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little); // PCM header size
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little); // bytes per second
  data.setUint16(32, 2, Endian.little); // bytes per frame
  data.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  File('assets/sounds/$name').writeAsBytesSync(data.buffer.asUint8List());
  stdout.writeln('assets/sounds/$name: ${samples.length / rate}s');
}

List<double> silence(double seconds) => List.filled((seconds * rate).round(), 0.0);

void main() {
  Directory('assets/sounds').createSync(recursive: true);

  // Default chime: two bright notes, up a fourth, like a soft doorbell
  final chime = silence(0.6);
  tone(chime, 0.0, 0.45, 1318.5, 0.45); // E6
  tone(chime, 0.13, 0.47, 1760.0, 0.45); // A6
  write('chime_default.wav', chime);

  // Urgent siren: three fast rising-and-falling sweeps, loud and hard to miss
  final urgent = silence(1.25);
  siren(urgent, 0.0, 0.4, 3, 700, 1500, 0.85);
  write('urgent_alert.wav', urgent);

  // Tactical pulse: two short, low knocks, quiet enough for a tent at night
  final pulse = silence(0.32);
  tone(pulse, 0.0, 0.1, 196.0, 0.5, decay: 30); // G3
  tone(pulse, 0.15, 0.1, 196.0, 0.5, decay: 30);
  write('tactical_pulse.wav', pulse);
}
