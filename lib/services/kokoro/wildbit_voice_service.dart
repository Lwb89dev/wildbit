import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'espeak_phonemizer.dart';
import 'kokoro_engine.dart';
import 'kokoro_model_manager.dart';
import 'kokoro_voices.dart';

/// On-device voice announcements for WildBit: "a POI is nearby", "track
/// saved", and so on — spoken with the Kokoro-82M neural TTS model so it
/// works with no connectivity, matching the app's offline-first design.
///
/// Distinct from Roadstr's turn-by-turn TTS service: hiking announcements
/// are infrequent and never time-critical, so this keeps a single-slot
/// pending queue instead of a priority/interruption system.
class WildBitVoiceService extends ChangeNotifier {
  final _phonemizer = EspeakPhonemizer.instance;
  final _engine = KokoroEngine.instance;
  final _player = AudioPlayer();

  String _language = 'it';
  String _gender = kKokoroDefaultGender;
  double _speed = 1.0;
  double _volume = 1.0;
  Float32List? _voiceData;
  bool _ready = false;
  bool _audioSessionConfigured = false;
  bool _isSpeaking = false;
  String? _pending;

  final Map<String, Float32List> _synthCache = {};
  static const _maxCacheEntries = 24;

  bool get isReady => _ready;
  String get language => _language;
  String get gender => _gender;
  double get speed => _speed;
  double get volume => _volume;

  void setGender(String gender) {
    if (gender == _gender) return;
    _gender = gender;
    _ready = false;
    notifyListeners();
  }

  void setSpeed(double speed) {
    _speed = speed;
    notifyListeners();
  }

  void setVolume(double volume) {
    _volume = volume;
    unawaited(_player.setVolume(volume));
    notifyListeners();
  }

  /// Convenience for app startup: loads the voice if the model has already
  /// been downloaded in a previous session, otherwise does nothing (the
  /// Settings screen is where the user starts a fresh download).
  Future<void> checkAndInit(String languageCode) async {
    try {
      final ready = await KokoroModelManager.instance.isReady({languageCode});
      if (ready) await init(languageCode);
    } catch (error) {
      // Voice output is optional. In particular, a desktop development
      // machine may not have the native eSpeak library installed; that must
      // never produce an unhandled asynchronous exception at app startup.
      _disableAfterFailure(error);
    }
  }

  /// Loads the voice for [languageCode], falling back silently (no
  /// announcements, no error) when the model hasn't been downloaded yet or
  /// the language has no Kokoro voice.
  Future<void> init(String languageCode) async {
    if (_ready && _language == languageCode) return;
    _language = languageCode;
    _ready = false;

    if (!kKokoroVoicesByLanguage.containsKey(_language)) return;
    final manager = KokoroModelManager.instance;
    final modelFile = await manager.modelFile;
    final voiceFile = await manager.voiceFile(_language, _gender);
    if (!await modelFile.exists() || !await voiceFile.exists()) return;

    try {
      _voiceData = (await voiceFile.readAsBytes()).buffer.asFloat32List();
      await _phonemizer.init();
      await _engine.init();
      await _configureAudioSession();
      _ready = true;
      notifyListeners();
      // Warm the exact Settings preview in the background. The first neural
      // synthesis otherwise happens only after the user taps play and feels
      // like the voice button has frozen.
      unawaited(_precache('Ciao! Sono Bit, la tua guida escursionistica.'));
    } catch (error) {
      _disableAfterFailure(error);
    }
  }

  Future<void> _configureAudioSession() async {
    if (_audioSessionConfigured) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _audioSessionConfigured = true;
  }

  /// Speaks [text] on-device. Queues at most one pending phrase (the newest
  /// wins) so a burst of announcements doesn't pile up.
  Future<void> speak(String text) async {
    if (!_ready) return;
    if (_isSpeaking) {
      _pending = text;
      return;
    }
    _isSpeaking = true;
    try {
      await _speakNow(text);
    } catch (error) {
      // A model/native-audio failure should degrade to silent guidance; it
      // must not bubble into GPS or track-recording flows.
      _disableAfterFailure(error);
    } finally {
      _isSpeaking = false;
      final next = _pending;
      _pending = null;
      if (next != null) unawaited(speak(next));
    }
  }

  Future<void> _speakNow(String text) async {
    final cacheKey = '$_language:$_gender:${_speed.toStringAsFixed(2)}:$text';
    var audio = _synthCache[cacheKey];
    if (audio == null) {
      final ipa = await _phonemizer.phonemize(text, _language);
      audio = await _engine.synthesize(ipa, _voiceData!, speed: _speed);
      _synthCache[cacheKey] = audio;
      while (_synthCache.length > _maxCacheEntries) {
        _synthCache.remove(_synthCache.keys.first);
      }
    }

    final wavFile = await _writeTempWav(audio);
    await _player.stop();
    await _player.setAudioSource(AudioSource.uri(Uri.file(wavFile.path)));
    await _player.setVolume(_volume);
    await _player.seek(Duration.zero);
    await _player.play();
    await _player.playerStateStream.firstWhere(
      (s) => s.processingState == ProcessingState.completed,
    );
  }

  Future<void> _precache(String text) async {
    if (!_ready || _voiceData == null) return;
    final cacheKey = '$_language:$_gender:${_speed.toStringAsFixed(2)}:$text';
    if (_synthCache.containsKey(cacheKey)) return;
    try {
      final ipa = await _phonemizer.phonemize(text, _language);
      final audio = await _engine.synthesize(ipa, _voiceData!, speed: _speed);
      _synthCache[cacheKey] = audio;
    } catch (_) {
      // A failed warm-up must never prevent normal voice guidance later.
    }
  }

  Future<File> _writeTempWav(Float32List audio) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/wildbit_voice_utterance.wav');
    await file.writeAsBytes(_float32ToWav(audio, 24000));
    return file;
  }

  void _disableAfterFailure(Object error) {
    _ready = false;
    _voiceData = null;
    debugPrint('WildBit voice disabled for this session: $error');
    notifyListeners();
  }

  // ── Hiking-specific announcements ─────────────────────────────────────────

  Future<void> announcePoiNearby(String name) => speak(_poiNearbyPhrase(name));
  Future<void> announceTrackStarted() => speak(_trackStartedPhrase());
  Future<void> announceTrackSaved() => speak(_trackSavedPhrase());

  String _poiNearbyPhrase(String name) => switch (_language) {
    'it' => 'Nelle vicinanze: $name',
    'es' => 'Cerca de aquí: $name',
    'fr' => 'À proximité : $name',
    'pt' => 'Nas proximidades: $name',
    _ => 'Nearby: $name',
  };

  String _trackStartedPhrase() => switch (_language) {
    'it' => 'Registrazione avviata',
    'es' => 'Grabación iniciada',
    'fr' => 'Enregistrement démarré',
    'pt' => 'Gravação iniciada',
    _ => 'Recording started',
  };

  String _trackSavedPhrase() => switch (_language) {
    'it' => 'Traccia salvata',
    'es' => 'Ruta guardada',
    'fr' => 'Trace enregistrée',
    'pt' => 'Trilha salva',
    _ => 'Track saved',
  };

  /// Encode a float32 PCM waveform as a standard 16-bit mono WAV.
  static Uint8List _float32ToWav(Float32List samples, int sampleRate) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    const blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = samples.length * blockAlign;

    final buf = ByteData(44 + dataSize);
    var p = 0;

    void ascii(String s) {
      for (final c in s.codeUnits) {
        buf.setUint8(p++, c);
      }
    }

    void u32(int v) {
      buf.setUint32(p, v, Endian.little);
      p += 4;
    }

    void u16(int v) {
      buf.setUint16(p, v, Endian.little);
      p += 2;
    }

    ascii('RIFF');
    u32(36 + dataSize);
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    u16(1);
    u16(numChannels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    ascii('data');
    u32(dataSize);

    for (final s in samples) {
      final v = (s * 32767).clamp(-32768, 32767).round();
      buf.setInt16(p, v, Endian.little);
      p += 2;
    }

    return buf.buffer.asUint8List();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
