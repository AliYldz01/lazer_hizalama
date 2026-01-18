import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:ui' as ui;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Uygulamayı yatay moda sabitliyoruz
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final cameras = await availableCameras();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: MerkezlemeAsistaniApp(cameras: cameras),
  ));
}

class MerkezlemeAsistaniApp extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MerkezlemeAsistaniApp({super.key, required this.cameras});

  @override
  State<MerkezlemeAsistaniApp> createState() => _MerkezlemeAsistaniAppState();
}

class _MerkezlemeAsistaniAppState extends State<MerkezlemeAsistaniApp> {
  CameraController? controller;
  Offset? lazerNoktasi;
  ui.Image? nozzlePhoto; 
  bool isLazerActive = false; 
  bool isAnalyzing = false;

  // Her mod için bağımsız ayar kayıtları
  Map<String, double> nozzleSettings = {
    'exposure': 0.0,
    'thresh': 100.0,
    'zoom': 1.0,
    'focus': 0.5,
  };

  Map<String, double> lazerSettings = {
    'exposure': -8.0, 
    'thresh': 220.0, 
    'zoom': 1.0,
    'focus': 1.0,
  };

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  void initCamera() async {
    controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );

    try {
      await controller!.initialize();
      await applyAllSettings();

      controller!.startImageStream((image) {
        if (!isAnalyzing) {
          isAnalyzing = true;
          analizEt(image);
          isAnalyzing = false;
        }
      });
    } catch (e) {
      debugPrint("Kamera başlatma hatası: $e");
    }
    
    if (mounted) setState(() {});
  }

  // Odaklama ve Pozlama ayarlarını zorla uygular
  Future<void> applyAllSettings() async {
    if (controller == null || !controller!.value.isInitialized) return;

    var s = isLazerActive ? lazerSettings : nozzleSettings;

    try {
      // Pozlama kontrolünü ele al
      await controller!.setExposureMode(ExposureMode.locked);
      await controller!.setExposureOffset(s['exposure']!);

      // Odaklama kontrolünü ele al (iPhone'da manual focus)
      await controller!.setFocusMode(FocusMode.locked);
      // Not: Mesafe ayarı iPhone donanımında focusPoint ile simüle edilir
      await controller!.setFocusPoint(Offset(s['focus']!, s['focus']!));

      await controller!.setZoomLevel(s['zoom']!);
    } catch (e) {
      debugPrint("Ayar uygulama hatası: $e");
    }
  }

  void analizEt(CameraImage image) {
    double sumX = 0;
    double sumY = 0;
    int count = 0;
    double currentThresh = isLazerActive ? lazerSettings['thresh']! : nozzleSettings['thresh']!;

    final bytes = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;

    for (int y = 0; y < height; y += 5) {
      for (int x = 0; x < width; x += 5) {
        int index = y * width + x;
        if (index < bytes.length && bytes[index] > currentThresh) {
          sumX += x;
          sumY += y;
          count++;
        }
      }
    }

    if (count > 5) {
      setState(() {
        lazerNoktasi = Offset(sumX / count, sumY / count);
      });
    } else {
      setState(() {
        lazerNoktasi = null;
      });
    }
  }

  void captureNozzle() async {
    final image = await controller!.takePicture();
    final bytes = await image.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() {
      nozzlePhoto = frame.image;
      isLazerActive = true; 
    });
    await applyAllSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // YAN YANA PENCERELER (YATAY MOD)
          Expanded(
            child: Row(
              children: [
                _buildWindow("CANLI: ${isLazerActive ? 'LAZER' : 'NOZZLE'}", CameraPreview(controller!), Colors.blue),
                _buildWindow(
                  "ANALİZ VE REFERANS", 
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      if (nozzlePhoto != null) RawImage(image: nozzlePhoto, fit: BoxFit.cover) 
                      else const Center(child: Text("Referans Bekleniyor...")),
                      if (lazerNoktasi != null)
                        CustomPaint(
                          size: Size.infinite,
                          painter: LazerMarkerPainter(lazerNoktasi!, controller!.value.previewSize!),
                        ),
                    ],
                  ), 
                  Colors.green
                ),
              ],
            ),
          ),
          
          // Alt Kontrol Barı (Daha şık ve işlevsel)
          Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFF1A1A1A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _modeBtn("1. NOZZLE", !isLazerActive, Colors.blue, () {
                  setState(() => isLazerActive = false);
                  applyAllSettings();
                }),
                _modeBtn("2. LAZER", isLazerActive, Colors.red, () {
                  setState(() => isLazerActive = true);
                  applyAllSettings();
                }),
                _actionBtn("REFERANS ÇEK", Colors.green, captureNozzle),
                IconButton(
                  icon: const Icon(Icons.settings_suggest, color: Colors.white, size: 30),
                  onPressed: _openSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindow(String title, Widget child, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.4), width: 2)),
        child: Stack(
          children: [
            Center(child: child),
            Container(
              padding: const EdgeInsets.all(4),
              color: Colors.black87,
              child: Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeBtn(String txt, bool active, Color color, VoidCallback tap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? color : Colors.grey[850],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: tap,
      child: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _actionBtn(String txt, Color color, VoidCallback tap) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(backgroundColor: color),
      onPressed: tap,
      icon: const Icon(Icons.camera, size: 18),
      label: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) {
          var s = isLazerActive ? lazerSettings : nozzleSettings;
          return AlertDialog(
            title: Text(isLazerActive ? "Lazer Ayarları" : "Nozzle Ayarları"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _slider(setDS, "Pozlama", s['exposure']!, -10, 10, (v) => s['exposure'] = v),
                  _slider(setDS, "Odak", s['focus']!, 0, 1, (v) => s['focus'] = v),
                  _slider(setDS, "Eşik (Threshold)", s['thresh']!, 0, 255, (v) => s['thresh'] = v),
                  _slider(setDS, "Zoom", s['zoom']!, 1, 10, (v) => s['zoom'] = v),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () { applyAllSettings(); Navigator.pop(context); }, child: const Text("KAYDET VE UYGULA")),
            ],
          );
        },
      ),
    );
  }

  Widget _slider(StateSetter setDS, String lbl, double val, double min, double max, Function(double) change) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$lbl: ${val.toStringAsFixed(1)}"),
        Slider(value: val, min: min, max: max, onChanged: (v) => setDS(() => change(v))),
      ],
    );
  }
}

class LazerMarkerPainter extends CustomPainter {
  final Offset pos;
  final Size previewSize;
  LazerMarkerPainter(this.pos, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    // Koordinat dönüşümü (Landscape düzeltmesi)
    final double scaleX = size.width / previewSize.height;
    final double scaleY = size.height / previewSize.width;
    final Offset mappedPos = Offset(pos.dx * scaleX, pos.dy * scaleY);

    final paint = Paint()..color = const Color(0xFF00FF00)..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawCircle(mappedPos, 15, paint);
    canvas.drawLine(Offset(mappedPos.dx - 20, mappedPos.dy), Offset(mappedPos.dx + 20, mappedPos.dy), paint);
    canvas.drawLine(Offset(mappedPos.dx, mappedPos.dy - 20), Offset(mappedPos.dx, mappedPos.dy + 20), paint);
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}