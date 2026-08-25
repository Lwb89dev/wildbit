import 'package:flutter/material.dart';

import 'map_rendering/mock/mock_valley_scene.dart';

/// Isolated live preview for the pixel-map prototype.
/// Run with: `flutter run -d linux -t lib/mock_preview_main.dart`.
void main() => runApp(const PixelMapPreviewApp());

class PixelMapPreviewApp extends StatelessWidget {
  const PixelMapPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WildBit · Pixel Map Lab',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF9CBC4A),
        scaffoldBackgroundColor: const Color(0xFF102A28),
        useMaterial3: true,
      ),
      home: const PixelMapPreviewScreen(),
    );
  }
}

class PixelMapPreviewScreen extends StatefulWidget {
  const PixelMapPreviewScreen({super.key});

  @override
  State<PixelMapPreviewScreen> createState() => _PixelMapPreviewScreenState();
}

class _PixelMapPreviewScreenState extends State<PixelMapPreviewScreen> {
  bool _showDebug = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pixel Map Lab · Valle mock'),
        actions: [
          IconButton(
            tooltip: _showDebug ? 'Nascondi debug' : 'Mostra debug',
            onPressed: () => setState(() => _showDebug = !_showDebug),
            icon: Icon(_showDebug ? Icons.grid_off : Icons.grid_on),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 900),
          child: AspectRatio(
            aspectRatio: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF739D50), width: 4),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 16),
                ],
              ),
              child: MockValleyScene(showDebug: _showDebug),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _showDebug
                ? 'Debug: footprint Bit, rifugio e cartello; assi del chunk.'
                : 'Mock: fiume, rive, bosco, sentiero, traccia, rifugio e Bit.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
