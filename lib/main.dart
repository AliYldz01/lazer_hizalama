import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:ui' as ui;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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

  Map<String, double> nozzleSettings = {
    'exposure': 0.0,
    'thresh': 100.0,
    'zoom': 1.0,
    'focus': 0.5,
  };

  Map<String, double> lazerSettings = {
    'exposure': -10.0, 
    'thresh': 240.0, 
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

  Future<void> applyAllSettings() async {
    if (controller == null || !controller!.value.isInitialized) return;
    var s = isLazerActive ? lazerSettings : nozzleSettings;

    try {
      await controller!.setExposureMode(ExposureMode.locked);
      await controller!.setExposureOffset(s['exposure']!);
      await controller!.setFocusMode(FocusMode.locked);
      await controller!.setFocusPoint(Offset(s['focus']!, s['focus']!));
      await controller!.setZoomLevel(s['zoom']!);
    } catch (e) {
      debugPrint("Ayar uygulama hatası: $e");
    }
  }

  // PYTHON MANTIĞI: Ağırlıklı Merkezleme (Weighted Centroid) Algoritması
  void analizEt(CameraImage image) {
    double weightedSumX = 0;
    double weightedSumY = 0;
    double totalWeight = 0;
    double currentThresh = isLazerActive ? lazerSettings['thresh']! : nozzleSettings['thresh']!;

    final bytes = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;

    for (int y = 0; y < height; y += 4) { 
      for (int x = 0; x < width; x += 4) {
        int index = y * width + x;
        if (index < bytes.length) {
          int brightness = bytes[index];
          if (brightness >= currentThresh) {
            // Sadece varlığına değil, parlaklık ağırlığına göre merkez hesaplar
            double weight = (brightness - currentThresh + 1).toDouble();
            weightedSumX += x * weight;
            weightedSumY += y * weight;
            totalWeight += weight;
          }
        }
      }
    }

    if (totalWeight > 0) {
      setState(() {
        lazerNoktasi = Offset(weightedSumX / totalWeight, weightedSumY / totalWeight);
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
          Expanded(
            child: Row(
              children: [
                // SOL EKRAN: Canlı Takip + Lazer İşareti (İyileştirme)
                _buildWindow("CANLI: ${isLazerActive ? 'LAZER' : 'NOZZLE'}", 
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller!),
                      if (lazerNoktasi != null)
                        CustomPaint(
                          painter: LazerMarkerPainter(lazerNoktasi!, controller!.value.previewSize!, Colors.redAccent),
                        ),
                    ],
                  ), 
                  Colors.blue),
                
                // SAĞ EKRAN: Referans + Lazer İşareti
                _buildWindow(
                  "ANALİZ VE REFERANS", 
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      if (nozzlePhoto != null) RawImage(image: nozzlePhoto, fit: BoxFit.cover) 
                      else const Center(child: Text("Referans Bekleniyor...")),
                      if (lazerNoktasi != null)
                        CustomPaint(
                          painter: LazerMarkerPainter(lazerNoktasi!, controller!.value.previewSize!, Colors.greenAccent),
                        ),
                    ],
                  ), 
                  Colors.green
                ),
              ],
            ),
          ),
          
          // YATAY ALT KONTROL PANELİ (İyileştirme)
          Container(
            height: 65,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            color: const Color(0xFF151515),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _modeBtn("NOZZLE", !isLazerActive, Colors.blue, () {
                      setState(() => isLazerActive = false);
                      applyAllSettings();
                    }),
                    const SizedBox(width: 12),
                    _modeBtn("LAZER", isLazerActive, Colors.red, () {
                      setState(() => isLazerActive = true);
                      applyAllSettings();
                    }),
                  ],
                ),
                _actionBtn("REFERANS ÇEK", Colors.green, captureNozzle),
                IconButton(
                  icon: const Icon(Icons.tune, color: Colors.white, size: 30),
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
    return SizedBox(
      height: 45,
      width: 110,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: active ? color : Colors.grey[850],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: tap,
        child: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _actionBtn(String txt, Color color, VoidCallback tap) {
    return SizedBox(
      height: 45,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: color),
        onPressed: tap,
        icon: const Icon(Icons.camera_alt, size: 20),
        label: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
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
  final Color color;
  LazerMarkerPainter(this.pos, this.previewSize, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / previewSize.height;
    final double scaleY = size.height / previewSize.width;
    final Offset mappedPos = Offset(pos.dx * scaleX, pos.dy * scaleY);

    final paint = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawCircle(mappedPos, 15, paint);
    canvas.drawLine(Offset(mappedPos.dx - 25, mappedPos.dy), Offset(mappedPos.dx + 25, mappedPos.dy), paint);
    canvas.drawLine(Offset(mappedPos.dx, mappedPos.dy - 25), Offset(mappedPos.dx, mappedPos.dy + 25), paint);
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}