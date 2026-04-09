import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton service for playing call ringtones/ringback tones.
///
/// Generates WAV files on disk and plays them via `just_audio`.
/// File-based playback is far more reliable on iOS than StreamAudioSource.
class RingtoneService {
  static final RingtoneService _instance = RingtoneService._internal();
  factory RingtoneService() => _instance;
  RingtoneService._internal();

  AudioPlayer? _player;
  Timer? _loopTimer;
  bool _isPlaying = false;

  // Cached file paths (generated once)
  String? _incomingRingtonePath;
  String? _outgoingRingbackPath;

  bool get isPlaying => _isPlaying;

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// Force audio output to speaker (not earpiece).
  /// On iOS, WebRTC may have set audio session to earpiece mode.
  Future<void> _forceSpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(true);
      debugPrint('[Ringtone] Forced speaker ON');
    } catch (e) {
      debugPrint('[Ringtone] setSpeakerphoneOn error (non-fatal): $e');
    }
  }

  /// Play incoming call ringtone (looping, LOUD).
  Future<void> playIncomingRingtone() async {
    await stop();
    _isPlaying = true;

    try {
      // Delete old cached file to pick up new amplitude
      _incomingRingtonePath = null;

      final path = await _getOrCreateWav(
        name: 'incoming_ringtone_v3',
        cachedPath: _incomingRingtonePath,
        onCached: (p) => _incomingRingtonePath = p,
        ringMs: 2000,
        silenceMs: 2000,
        totalMs: 60000, // 60 seconds of ringing
        freqs: [440.0, 480.0],
        amplitude: 28000, // near-max 16-bit amplitude
      );

      await _forceSpeaker();

      _player = AudioPlayer();
      await _player!.setFilePath(path);
      await _player!.setLoopMode(LoopMode.all);
      await _player!.setVolume(1.0);
      await _player!.play();
      debugPrint('[Ringtone] Incoming ringtone PLAYING LOUD from $path');
    } catch (e, s) {
      debugPrint('[Ringtone] Incoming ringtone error: $e\n$s');
      _startHapticPattern();
    }
  }

  /// Play outgoing call ringback tone (ring…pause…ring, LOUD through speaker).
  Future<void> playOutgoingRingback() async {
    await stop();
    _isPlaying = true;

    try {
      // Delete old cached file to pick up new amplitude
      _outgoingRingbackPath = null;

      final path = await _getOrCreateWav(
        name: 'outgoing_ringback_v3',
        cachedPath: _outgoingRingbackPath,
        onCached: (p) => _outgoingRingbackPath = p,
        ringMs: 2000,
        silenceMs: 3000,
        totalMs: 60000, // 60 seconds until answered/timeout
        freqs: [440.0, 480.0],
        amplitude: 28000, // near-max 16-bit amplitude
      );

      await _forceSpeaker();

      _player = AudioPlayer();
      await _player!.setFilePath(path);
      await _player!.setLoopMode(LoopMode.all);
      await _player!.setVolume(1.0);
      await _player!.play();
      debugPrint('[Ringtone] Outgoing ringback PLAYING LOUD from $path');
    } catch (e, s) {
      debugPrint('[Ringtone] Outgoing ringback error: $e\n$s');
      _startHapticPattern();
    }
  }

  /// Stop any currently playing ringtone.
  Future<void> stop() async {
    _isPlaying = false;
    _loopTimer?.cancel();
    _loopTimer = null;

    try {
      if (_player != null) {
        await _player!.stop();
        await _player!.dispose();
        _player = null;
        debugPrint('[Ringtone] Stopped');
      }
    } catch (e) {
      debugPrint('[Ringtone] stop error: $e');
      _player = null;
    }
  }

  void dispose() => stop();

  // ---------------------------------------------------------------------------
  // WAV FILE GENERATION (cached on disk)
  // ---------------------------------------------------------------------------

  Future<String> _getOrCreateWav({
    required String name,
    required String? cachedPath,
    required void Function(String) onCached,
    required int ringMs,
    required int silenceMs,
    required int totalMs,
    required List<double> freqs,
    required int amplitude,
  }) async {
    // Return cached path if file still exists
    if (cachedPath != null && File(cachedPath).existsSync()) {
      return cachedPath;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name.wav');

    final bytes = _generateWav(
      sampleRate: 44100,
      frequencies: freqs,
      ringMs: ringMs,
      silenceMs: silenceMs,
      totalDurationMs: totalMs,
      amplitude: amplitude,
    );

    await file.writeAsBytes(bytes, flush: true);
    debugPrint('[Ringtone] Generated WAV: ${file.path} (${bytes.length} bytes)');
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
    final cycleSamples = ringSamples + (sampleRate * silenceMs / 1000).round();

    final pcm = Int16List(totalSamples);

    for (int i = 0; i < totalSamples; i++) {
      final posInCycle = i % cycleSamples;
      if (posInCycle < ringSamples) {
        double sample = 0;
        for (final freq in frequencies) {
          sample += sin(2 * pi * freq * i / sampleRate);
        }
        // Fade envelope (50ms)
        final fadeLen = (sampleRate * 0.05).round();
        double env = 1.0;
        if (posInCycle < fadeLen) {
          env = posInCycle / fadeLen;
        } else if (posInCycle > ringSamples - fadeLen) {
          env = (ringSamples - posInCycle) / fadeLen;
        }
        pcm[i] = (sample / frequencies.length * amplitude * env)
            .round()
            .clamp(-32768, 32767);
      } else {
        pcm[i] = 0;
      }
    }

    final dataSize = totalSamples * 2;
    final fileSize = 36 + dataSize;
    final wav = ByteData(44 + dataSize);

    // RIFF header
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
