import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Singleton service for playing call ringtones/ringback tones.
///
/// - **Incoming call**: Looping ringtone pattern (played by in-app UI).
///   Note: iOS CallKit natively plays ringtone — this is for the Flutter screen.
/// - **Outgoing call**: Ringback tone (ring…pause…ring) so the caller knows it's ringing.
class RingtoneService {
  static final RingtoneService _instance = RingtoneService._internal();
  factory RingtoneService() => _instance;
  RingtoneService._internal();

  AudioPlayer? _player;
  Timer? _loopTimer;
  bool _isPlaying = false;
  StreamSubscription? _playerSub;

  bool get isPlaying => _isPlaying;

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Play incoming call ringtone (looping, higher volume).
  Future<void> playIncomingRingtone() async {
    await stop();
    _isPlaying = true;

    try {
      _player = AudioPlayer();
      final source = _RingToneSource(
        sampleRate: 44100,
        frequencies: [440.0, 480.0], // North-American style dual-tone
        ringMs: 2000,
        silenceMs: 4000,
        totalDurationMs: 30000, // 30 seconds of ringing
      );
      await _player!.setAudioSource(source);
      await _player!.setLoopMode(LoopMode.all);
      await _player!.setVolume(0.85);
      await _player!.play();
      debugPrint('[Ringtone] Incoming ringtone started');
    } catch (e) {
      debugPrint('[Ringtone] Incoming ringtone error: $e');
      // Fallback: haptic
      _startHapticPattern();
    }
  }

  /// Play outgoing call ringback tone (ring…pause…ring, quieter).
  Future<void> playOutgoingRingback() async {
    await stop();
    _isPlaying = true;

    try {
      _player = AudioPlayer();
      final source = _RingToneSource(
        sampleRate: 44100,
        frequencies: [440.0, 480.0],
        ringMs: 2000,
        silenceMs: 4000,
        totalDurationMs: 60000, // 60 seconds (until answered or timeout)
      );
      await _player!.setAudioSource(source);
      await _player!.setLoopMode(LoopMode.all);
      await _player!.setVolume(0.45);
      await _player!.play();
      debugPrint('[Ringtone] Outgoing ringback started');
    } catch (e) {
      debugPrint('[Ringtone] Outgoing ringback error: $e');
      _startHapticPattern();
    }
  }

  /// Stop any currently playing ringtone.
  Future<void> stop() async {
    _isPlaying = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    _playerSub?.cancel();
    _playerSub = null;

    try {
      if (_player != null) {
        await _player!.stop();
        await _player!.dispose();
        _player = null;
      }
    } catch (e) {
      debugPrint('[Ringtone] stop error: $e');
      _player = null;
    }
  }

  void dispose() => stop();

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

// =============================================================================
// PCM Ringtone Audio Source — generates a WAV ringtone in memory.
// =============================================================================

/// Generates a WAV ringtone with dual-tone frequencies.
/// Pattern: [ring for `ringMs`] then [silence for `silenceMs`], repeated.
class _RingToneSource extends StreamAudioSource {
  final int sampleRate;
  final List<double> frequencies;
  final int ringMs;
  final int silenceMs;
  final int totalDurationMs;

  late final Uint8List _bytes;

  _RingToneSource({
    required this.sampleRate,
    required this.frequencies,
    required this.ringMs,
    required this.silenceMs,
    required this.totalDurationMs,
  }) {
    _bytes = _generateWav();
  }

  Uint8List _generateWav() {
    final totalSamples = (sampleRate * totalDurationMs / 1000).round();
    final ringSamples = (sampleRate * ringMs / 1000).round();
    final silenceSamples = (sampleRate * silenceMs / 1000).round();
    final cycleSamples = ringSamples + silenceSamples;

    // 16-bit mono PCM
    final pcm = Int16List(totalSamples);
    const amplitude = 8000; // not too loud

    for (int i = 0; i < totalSamples; i++) {
      final posInCycle = i % cycleSamples;
      if (posInCycle < ringSamples) {
        // Sum the frequencies (dual-tone)
        double sample = 0;
        for (final freq in frequencies) {
          sample += sin(2 * pi * freq * i / sampleRate);
        }
        // Apply fade-in / fade-out envelope at edges (50ms)
        final fadeLen = (sampleRate * 0.05).round();
        double env = 1.0;
        if (posInCycle < fadeLen) {
          env = posInCycle / fadeLen;
        } else if (posInCycle > ringSamples - fadeLen) {
          env = (ringSamples - posInCycle) / fadeLen;
        }
        pcm[i] = (sample / frequencies.length * amplitude * env).round().clamp(-32768, 32767);
      } else {
        pcm[i] = 0;
      }
    }

    // Build WAV file
    final dataSize = totalSamples * 2; // 16-bit = 2 bytes
    final fileSize = 36 + dataSize;
    final wav = ByteData(44 + dataSize);

    // RIFF header
    wav.setUint8(0, 0x52); // 'R'
    wav.setUint8(1, 0x49); // 'I'
    wav.setUint8(2, 0x46); // 'F'
    wav.setUint8(3, 0x46); // 'F'
    wav.setUint32(4, fileSize, Endian.little);
    wav.setUint8(8, 0x57);  // 'W'
    wav.setUint8(9, 0x41);  // 'A'
    wav.setUint8(10, 0x56); // 'V'
    wav.setUint8(11, 0x45); // 'E'

    // fmt sub-chunk
    wav.setUint8(12, 0x66); // 'f'
    wav.setUint8(13, 0x6D); // 'm'
    wav.setUint8(14, 0x74); // 't'
    wav.setUint8(15, 0x20); // ' '
    wav.setUint32(16, 16, Endian.little); // sub-chunk size
    wav.setUint16(20, 1, Endian.little);  // PCM format
    wav.setUint16(22, 1, Endian.little);  // mono
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    wav.setUint16(32, 2, Endian.little); // block align
    wav.setUint16(34, 16, Endian.little); // bits per sample

    // data sub-chunk
    wav.setUint8(36, 0x64); // 'd'
    wav.setUint8(37, 0x61); // 'a'
    wav.setUint8(38, 0x74); // 't'
    wav.setUint8(39, 0x61); // 'a'
    wav.setUint32(40, dataSize, Endian.little);

    // PCM data
    for (int i = 0; i < totalSamples; i++) {
      wav.setInt16(44 + i * 2, pcm[i], Endian.little);
    }

    return wav.buffer.asUint8List();
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream.value(_bytes.sublist(s, e)),
      contentType: 'audio/wav',
    );
  }
}
