import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_audio_capture/flutter_audio_capture.dart';
import 'package:fftea/fftea.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

void main() {
  runApp(const LiveSplitAudioApp());
}

// --- PUNTO DE ENTRADA DE LA VENTANA FLOTANTE (OVERLAY) ---
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FloatingTimerWidget(),
    ),
  );
}

class LiveSplitAudioApp extends StatelessWidget {
  const LiveSplitAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoSplitter GTA SA',
      theme: ThemeData.dark(),
      home: const SplitterHomeScreen(),
    );
  }
}

// ==========================================
// PANTALLA PRINCIPAL (CONFIGURACIÓN Y MIC)
// ==========================================
class SplitterHomeScreen extends StatefulWidget {
  const SplitterHomeScreen({super.key});

  @override
  State<SplitterHomeScreen> createState() => _SplitterHomeScreenState();
}

class _SplitterHomeScreenState extends State<SplitterHomeScreen> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _displayTimer;
  
  final FlutterAudioCapture _audioCapture = FlutterAudioCapture();
  bool _isListening = false;
  DateTime _lastSplitTime = DateTime.now();

  static const int _sampleRate = 44100;
  static const double _targetFrequency = 1046.0; // Nota C6 (Misión Superada)
  static const double _thresholdDb = -15.0;

  @override
  void initState() {
    super.initState();
    _requestAllPermissions();
  }

  Future<void> _requestAllPermissions() async {
    await Permission.microphone.request();
    bool? isGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (isGranted == null || !isGranted) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  void _startTimer() async {
    _stopwatch.start();
    
    if (await FlutterOverlayWindow.isPermissionGranted() == true) {
      await FlutterOverlayWindow.showOverlay(
        height: 120,
        width: 250,
        alignment: OverlayAlignment.topCenter,
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.none,
      );
    }

    _displayTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      setState(() {});
      FlutterOverlayWindow.shareData(_formatTime(_stopwatch.elapsedMilliseconds));
    });
    
    _startAudioListening();
  }

  void _stopTimer() async {
    _stopwatch.stop();
    _displayTimer?.cancel();
    _stopAudioListening();
    await FlutterOverlayWindow.closeOverlay();
    setState(() {});
  }

  String _formatTime(int milliseconds) {
    int hundreds = (milliseconds / 10).truncate() % 100;
    int seconds = (milliseconds / 1000).truncate() % 60;
    int minutes = (milliseconds / (1000 * 60)).truncate() % 60;
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${hundreds.toString().padLeft(2, '0')}";
  }

  Future<void> _startAudioListening() async {
    await _audioCapture.start(_onAudioData, _onError, sampleRate: _sampleRate, bufferSize: 2048);
    setState(() => _isListening = true);
  }

  Future<void> _stopAudioListening() async {
    await _audioCapture.stop();
    setState(() => _isListening = false);
  }

  void _onAudioData(dynamic obj) {
    if (!_stopwatch.isRunning) return;
    List<double> buffer = Float32List.fromList(List<double>.from(obj));
    if (buffer.length < 1024) return;

    final stft = STFT(buffer.length);
    final spectrum = stft.fft(buffer);
    double freqResolution = _sampleRate / buffer.length;
    int targetIndex = (_targetFrequency / freqResolution).round();

    if (targetIndex < spectrum.length) {
      double magnitude = spectrum[targetIndex].abs();
      double db = 20 * log(magnitude + 1e-6) / ln10;

      if (db > _thresholdDb) {
        if (DateTime.now().difference(_lastSplitTime).inSeconds >= 3) {
          _lastSplitTime = DateTime.now();
          FlutterOverlayWindow.shareData("SPLIT! ${_formatTime(_stopwatch.elapsedMilliseconds)}");
        }
      }
    }
  }

  void _onError(Object e) => debugPrint("Error: $e");

  @override
  void dispose() {
    _displayTimer?.cancel();
    _stopAudioListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar AutoSplitter GTA SA')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_formatTime(_stopwatch.elapsedMilliseconds), style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _stopwatch.isRunning ? _stopTimer : _startTimer,
              style: ElevatedButton.styleFrom(backgroundColor: _stopwatch.isRunning ? Colors.red : Colors.green),
              child: Text(_stopwatch.isRunning ? 'Detener y Ocultar Overlay' : 'Iniciar y Lanzar Overlay'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// WIDGET DE LA VENTANA FLOTANTE (SOBRE EL JUEGO)
// ==========================================
class FloatingTimerWidget extends StatefulWidget {
  const FloatingTimerWidget({super.key});

  @override
  State<FloatingTimerWidget> createState() => _FloatingTimerWidgetState();
}

class _FloatingTimerWidgetState extends State<FloatingTimerWidget> {
  String _timeText = "00:00.00";

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.listener.listen((data) {
      setState(() {
        _timeText = data.toString();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green, width: 2),
        ),
        child: Center(
          child: Text(
            _timeText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
