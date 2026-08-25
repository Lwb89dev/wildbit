import 'package:flutter/material.dart';

import 'map_rendering/mock/mock_valley_scene.dart';

/// Interactive desktop preview for the pixel compositor.
///
/// Run with:
/// `flutter run -d linux --no-pub -t lib/interactive_mock_preview_main.dart`
void main() => runApp(const InteractiveMockPreviewApp());

class InteractiveMockPreviewApp extends StatelessWidget {
  const InteractiveMockPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WildBit · Interactive Pixel Map',
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF9CBC4A),
      scaffoldBackgroundColor: const Color(0xFF102A28),
      useMaterial3: true,
    ),
    home: const _InteractiveMockScreen(),
  );
}

class _InteractiveMockScreen extends StatefulWidget {
  const _InteractiveMockScreen();

  @override
  State<_InteractiveMockScreen> createState() => _InteractiveMockScreenState();
}

class _InteractiveMockScreenState extends State<_InteractiveMockScreen> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double delta) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current + delta).clamp(.55, 3.5).toDouble();
    _transform.value = Matrix4.identity()..scaleByDouble(next, next, next, 1);
  }

  void _reset() => _transform.value = Matrix4.identity()
    ..scaleByDouble(.86, .86, .86, 1);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('WildBit · Mock interattivo'),
          Text(
            'bosco · lago · rifugi · ponte sul fiume',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Centra vista',
          onPressed: _reset,
          icon: const Icon(Icons.center_focus_strong),
        ),
      ],
    ),
    body: Stack(
      children: [
        InteractiveViewer(
          transformationController: _transform,
          constrained: false,
          minScale: .55,
          maxScale: 3.5,
          boundaryMargin: const EdgeInsets.all(180),
          clipBehavior: Clip.hardEdge,
          child: const SizedBox(
            width: 640,
            height: 640,
            child: MockValleyScene(showLake: true),
          ),
        ),
        Positioned(
          right: 18,
          bottom: 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'zoom-in',
                tooltip: 'Zoom avanti',
                onPressed: () => _zoom(.25),
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'zoom-out',
                tooltip: 'Zoom indietro',
                onPressed: () => _zoom(-.25),
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),
        const Positioned(
          left: 18,
          bottom: 18,
          child: _HintPill(),
        ),
      ],
    ),
  );
}

class _HintPill extends StatelessWidget {
  const _HintPill();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xDD102A28),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0x55739D50)),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Text('Trascina per spostarti · rotella/pinch per zoomare'),
    ),
  );
}
