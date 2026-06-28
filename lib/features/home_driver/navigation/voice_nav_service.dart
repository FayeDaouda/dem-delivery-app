import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'directions_service.dart';

const _kVoiceNavEnabled = 'dem_voice_nav_enabled';

class VoiceNavService {
  VoiceNavService._();
  static final instance = VoiceNavService._();

  final _tts = FlutterTts();
  bool _initialized = false;
  bool _enabled = false;
  bool _speaking = false;

  List<RouteStep> _steps = [];
  int _currentStepIndex = 0;
  String? _lastSpokenId;
  DateTime? _lastSpoke;

  bool get enabled => _enabled;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    _tts.setCompletionHandler(() => _speaking = false);

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kVoiceNavEnabled) ?? true;
  }

  Future<void> toggle() async {
    _enabled = !_enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVoiceNavEnabled, _enabled);
    if (!_enabled) {
      await _tts.stop();
      _speaking = false;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kVoiceNavEnabled, value);
    if (!value) {
      await _tts.stop();
      _speaking = false;
    }
  }

  void updateSteps(List<RouteStep> steps) {
    _steps = steps;
    _currentStepIndex = 0;
    _lastSpokenId = null;
  }

  void onPositionUpdate(Position position) {
    if (!_enabled || _steps.isEmpty) return;

    final driverPos = LatLng(position.latitude, position.longitude);
    final closest = _findClosestStepIndex(driverPos);

    if (closest > _currentStepIndex) {
      _currentStepIndex = closest;
    }

    _checkAndSpeak(driverPos);
  }

  void _checkAndSpeak(LatLng driverPos) {
    if (_steps.isEmpty || _currentStepIndex >= _steps.length) return;

    final step = _steps[_currentStepIndex];
    final distToStep = _distanceMeters(driverPos, step.startLocation);

    final nextIdx = _currentStepIndex + 1;
    if (nextIdx < _steps.length) {
      final nextStep = _steps[nextIdx];
      final distToNext = _distanceMeters(driverPos, nextStep.startLocation);
      final speakId = 'step_$nextIdx';

      if (distToNext <= 150 && distToNext > 30 && _lastSpokenId != '${speakId}_prepare') {
        _speak(_prepareInstruction(nextStep, distToNext.round()));
        _lastSpokenId = '${speakId}_prepare';
        return;
      }

      if (distToNext <= 30 && _lastSpokenId != '${speakId}_now') {
        _speak(_nowInstruction(nextStep));
        _lastSpokenId = '${speakId}_now';
        _currentStepIndex = nextIdx;
        return;
      }
    }

    if (_currentStepIndex == 0 && _lastSpokenId == null && distToStep < 200) {
      _speak(step.instruction);
      _lastSpokenId = 'step_0_init';
    }
  }

  String _prepareInstruction(RouteStep step, int meters) {
    final dist = meters >= 100 ? '${(meters / 100).round() * 100} mètres' : '$meters mètres';
    final action = _maneuverToFrench(step.maneuver);
    if (action.isNotEmpty) return 'Dans $dist, $action';
    return 'Dans $dist, ${step.instruction}';
  }

  String _nowInstruction(RouteStep step) {
    final action = _maneuverToFrench(step.maneuver);
    if (action.isNotEmpty) return action;
    return step.instruction;
  }

  String _maneuverToFrench(String maneuver) => switch (maneuver) {
    'turn-left'          => 'tournez à gauche',
    'turn-right'         => 'tournez à droite',
    'turn-slight-left'   => 'tournez légèrement à gauche',
    'turn-slight-right'  => 'tournez légèrement à droite',
    'turn-sharp-left'    => 'tournez fortement à gauche',
    'turn-sharp-right'   => 'tournez fortement à droite',
    'uturn-left'         => 'faites demi-tour à gauche',
    'uturn-right'        => 'faites demi-tour à droite',
    'keep-left'          => 'serrez à gauche',
    'keep-right'         => 'serrez à droite',
    'merge'              => 'insérez-vous',
    'fork-left'          => 'prenez la fourche à gauche',
    'fork-right'         => 'prenez la fourche à droite',
    'ramp-left'          => 'prenez la bretelle à gauche',
    'ramp-right'         => 'prenez la bretelle à droite',
    'roundabout-left'    => 'au rond-point, prenez à gauche',
    'roundabout-right'   => 'au rond-point, prenez à droite',
    'straight'           => 'continuez tout droit',
    _                    => '',
  };

  int _findClosestStepIndex(LatLng pos) {
    int closest = _currentStepIndex;
    double minDist = double.infinity;
    final searchEnd = (_currentStepIndex + 5).clamp(0, _steps.length);
    for (int i = _currentStepIndex; i < searchEnd; i++) {
      final d = _distanceMeters(pos, _steps[i].startLocation);
      if (d < minDist) {
        minDist = d;
        closest = i;
      }
    }
    return closest;
  }

  double _distanceMeters(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
  }

  Future<void> _speak(String text) async {
    if (!_enabled || text.isEmpty) return;
    final now = DateTime.now();
    if (_lastSpoke != null && now.difference(_lastSpoke!).inSeconds < 3) return;
    _lastSpoke = now;

    if (_speaking) await _tts.stop();
    _speaking = true;
    await _tts.speak(text);
  }

  Future<void> speakDirect(String text) async {
    if (!_enabled) return;
    if (_speaking) await _tts.stop();
    _speaking = true;
    await _tts.speak(text);
  }

  void onPhaseChanged({required bool isPickedUp}) {
    _steps = [];
    _currentStepIndex = 0;
    _lastSpokenId = null;
    if (_enabled) {
      speakDirect(isPickedUp
          ? 'Colis récupéré. En route vers la livraison.'
          : 'En route vers le point de collecte.');
    }
  }

  void onArrival({required bool isPickup}) {
    if (_enabled) {
      speakDirect(isPickup
          ? 'Vous êtes arrivé au point de collecte.'
          : 'Vous êtes arrivé à destination.');
    }
  }

  Future<void> dispose() async {
    await _tts.stop();
    _speaking = false;
    _steps = [];
    _currentStepIndex = 0;
    _lastSpokenId = null;
  }
}
