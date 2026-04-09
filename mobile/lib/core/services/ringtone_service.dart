import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton service for playing call ringtones/ringback tones.
///
/// Uses native iOS AVAudioPlayer via MethodChannel to avoid audio session
/// conflicts with flutter_webrtc (just_audio fights over AVAudioSession).
///
/// Generates a small WAV file (one ring cycle ~5s), loops it natively.
class RingtoneService {
  static final RingtoneService _instance = RingtoneService._internal();
  factory RingtoneService() => _instance;
  RingtoneService._internal();

  static const _channel = MethodChannel('com.londonsnaps.ringtone');

  Timer? _loopTimer;
  bool _isPlaying = false;

  // Cached file paths
  String? _incomingPath;
  String? _outgoingPath;

  bool get isPlaying => _isPlaying;

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Play incoming call ringtone (looping, LOUD).
  Future<void> playIncomingRingtone() async {
    await stop();
    _isPlaying = true;

    try {
      final path = await _getOrCreateWav(
        name: 'ring_in_v4',
        cachedPath: _incomingPath,
        onCached: (p) => _incomingPath = p,
        ringMs: 2000,
        silenceMs: 2000,
        freqs: [440.0, 480.0],
        amplitude: 30000,
      );

      await _playNative(path, loop: true, volume: 1.0);
      debugPrint('[Ringtone] Incoming ringtone PLAYING from $path');
    } catch (e, s) {
      debugPrint('[Ringtone] Incoming error: $e\n$s');
      _startHapticPattern();
    }
  }

  /// Play outgoing ringback tone (looping, LOUD).
  Future<void> playOutgoingRingback() async {
    await stop();
    _isPlaying = true;

    try {
      final path = await _getOrCreateWav(
        name: 'ring_out_v4',
        cachedPath: _outgoingPath,
        onCached: (p) => _outgoingPath = p,
        ringMs: 2000,
        silenceMs: 3000,
        freqs: [440.0, 480.0],
        amplitude: 30000,
      );

      await _playNative(path, loop: true, volume: 1.0);
      debugPrint('[Ringtone] Outgoing ringback PLAYING from $path');
    } catch (e, s) {
      debugPrint('[Ringtone] Outgoing error: $e\n$s');
      _startHapticPattern();
    }
  }

  /// Stop any currently playing ringtone.
  Future<void> stop() async {
    _isPlaying = false;
    _loopTimer?.cancel();
    _loopTimer = null;

    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('[Ringtone] stop error: $e');
    }
  }

  void dispose() => stop();

  // ---------------------------------------------------------------------------
  // NATIVE PLAYBACK via MethodChannel
  // ---------------------------------------------------------------------------

  Future<void> _playNative(String path, {required bool loop, required double volume}) async {
    try {
      await _channel.invokeMethod('play', {
        'path': path,
        'loop': loop,
        'volume': volume,
      });
    } on MissingPluginException {
      // Native side not implemented yet, fall back to platform sound
      debugPrint('[Ringtone] Native channel not available, using system fallback');
      _startSystemSoundLoop();
    }
  }

  /// Fallback: use SystemSound in a timer loop
  void _startSystemSoundLoop() {
    _isPlaying = true;
    void doRing() {
      if (!_isPlaying) return;
      SystemSound.play(SystemSoundType.alert);
      _loopTimer = Timer(const Duration(seconds: 3), doRing);
    }
    doRing();
  }

  // ---------------------------------------------------------------------------
  // WAV FILE GENERATION (one cycle, looped by native player)
  // ---------------------------------------------------------------------------

  Future<String> _getOrCreateWav({
    required String name,
    required String? cachedPath,
    required void Function(String) onCached,
    required int ringMs,
    required int silenceMs,
    required List<double> freqs,
    required int amplitude,
  }) async {
    if (cachedPath != null && File(cachedPath).existsSync()) {
      return cachedPath;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name.wav');

    // Generate ONLY one cycle (ring + silence), ~5 seconds
    // Native player loops it infinitely
    final totalMs = ringMs + silenceMs;
    final bytes = _generateWav(
      sampleRate: 44100,
      frequencies: freqs,
      ringMs: ringMs,
      silenceMs: silenceMs,
      totalDurationMs: totalMs,
      amplitude: amplitude,
    );

    await file.writeAsBytes(bytes, flush: true);
    debugPrint('[Ringtone] WAV generated: ${file.path} (${bytes.length} bytes)');
    onCached(file.path);
    return file.path;
  }

  Uint8List _generateWav({
    required int sampleRate,
    required List<double> frequencies,
    required int ringMs,
    required int silenceMs,
    required int totalDurationMs,
    required int amplitude,
  }) {
    final totalSamples = (sampleRate * totalDurationMs / 1000).round();
    final ringSamples = (sampleRate * ringMs / 1000).round();

    final pcm = Int16List(totalSamples);

    for (int i = 0; i < totalSamples; i++) {
      if (i < ringSamples) {
        double sample = 0;
        for (final freq in frequencies) {
          sample += sin(2 * pi * freq * i / sampleRate);
        }
        // Fade envelope (30ms)
        final fadeLen = (sampleRate * 0.03).round();
        double env = 1.0;
        if (i < fadeLen) {
          env = i / fadeLen;
        } else if (i > ringSamples - fadeLen) {
          env = (ringSamples - i) / fadeLen;
        }
        pcm[i] = (sample / frequencies.length * amplitude * env)
            .round()
            .clamp(-32768, 32767);
      }
      // else: silence (already 0)
    }

    final dataSize = totalSamples * 2;
    final fileSize = 36 + dataSize;
    final wav = ByteData(44 + dataSize);

    // RIFF
    wav.setUint8(0, 0x52); wav.setUint8(1, 0x49);
    wav.setUint8(2, 0x46); wav.setUint8(3, 0x46);
    wav.setUint32(4, fileSize, Endian.little);
    wav.setUint8(8, 0x57); wav.setUint8(9, 0x41);
    wav.setUint8(10, 0x56); wav.setUint8(11, 0x45);
    // fmt
    wav.setUint8(12, 0x66); wav.setUint8(13, 0x6D);
    wav.setUint8(14, 0x74); wav.setUint8(15, 0x20);
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);
    wav.setUint16(22, 1, Endian.little);
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, sampleRate * 2, Endian.little);
    wav.setUint16(32, 2, Endian.little);
    wav.setUint16(34, 16, Endian.little);
    // data
    wav.setUint8(36, 0x64); wav.setUint8(37, 0x61);
    wav.setUint8(38, 0x74); wav.setUint8(39, 0x61);
    wav.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < totalSamples; i++) {
      wav.setInt16(44 + i * 2, pcm[i], Endian.little);
    }

    return wav.buffer.asUint8List();
  }

  // ---------------------------------------------------------------------------
  // HAPTIC FALLBACK
  // ---------------------------------------------------------------------------

  void _startHapticPattern() {
    _isPlaying = true;
    void doRing() {
      if (!_isPlaying) return;
      HapticFeedback.heavyImpact();
      _loopTimer = Timer(const Duration(milliseconds: 600), () {
        if (!_isPlaying) return;
        HapticFeedback.heavyImpact();
        _loopTimer = Timer(const Duration(seconds: 3), doRing);
      });
    }
    doRing();
  }
}
