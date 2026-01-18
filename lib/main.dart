import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Ekran kilidi için gerekli
import 'package:camera/camera.dart';
import 'dart:ui' as ui;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // UYGULAMAYI YATAY MODA ZORLA
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

  Map<String, double> nozzleSettings = {'exposure': -2.0, 'thresh': 150.0, 'zoom': 1.0};
  Map<String, double> lazerSettings = {'exposure': -8.0, 'thresh': 220.0, 'zoom': 1.0};

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  void initCamera() async {
    controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );

    await controller!.initialize();
    applyModeSettings();

    controller!.startImageStream((image) {
      if (!isAnalyzing) {
        isAnalyzing = true;
        analizEt(image);
        isAnalyzing = false;
      }
    });
    if (mounted) setState(() {});
  }

  void applyModeSettings() {
    var s = isLazerActive ? lazerSettings : nozzleSettings;
    controller!.setZoomLevel(s['zoom']!);
    controller!.setExposureOffset(s['exposure']!);
  }

  void analizEt(CameraImage image) {
    double sumX = 0;
    double sumY = 0;
    int count = 0;
    double currentThresh = isLazerActive ? lazerSettings['thresh']! : nozzleSettings['thresh']!;

    final bytes = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;

    for (int y = 0; y < height; y += 4) {
      for (int x = 0; x < width; x += 4) {
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
      applyModeSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Telefonun kendi yönünü dikkate almadan yatay layout kuruyoruz
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        toolbarHeight: 40,
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("PRO-Laser Landscape | Secure Mode", style: TextStyle(fontSize: 12)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            onPressed: () => _showSettingsDialog(),
          )
        ],
      ),
      body: Column(
        children: [
          // YATAYDA YAN YANA EKRANLAR (PYTHON GİBİ)
          Expanded(
            child: Row(
              children: [
                _buildScreenFrame("CANLI GÖRÜNTÜ", CameraPreview(controller!), Colors.blue),
                _buildScreenFrame(
                  "HİZALAMA REFERANSI", 
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
          
          // Kontrol Çubuğu (Daha ince, yatay ekran için optimize)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
            color: const Color(0xFF1E1E1E),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _controlButton("1. NOZZLE MODU", !isLazerActive, Colors.blue, () {
                  setState(() { isLazerActive = false; applyModeSettings(); });
                }),
                _controlButton("2. LAZER MODU", isLazerActive, Colors.red, () {
                  setState(() { isLazerActive = true; applyModeSettings(); });
                }),
                _controlButton("REFERANS ÇEK", false, Colors.green, captureNozzle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenFrame(String title, Widget child, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5)),
        child: Stack(
          children: [
            Center(child: child),
            Positioned(
              top: 2, 
              left: 2, 
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: Colors.black54, 
                child: Text(title, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold))
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton(String label, bool active, Color color, VoidCallback tap) {
    return SizedBox(
      height: 35,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: active ? color : Colors.grey[800],
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: tap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          var s = isLazerActive ? lazerSettings : nozzleSettings;
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text(isLazerActive ? "Lazer Ayarları" : "Nozzle Ayarları", style: const TextStyle(fontSize: 14)),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _slider(setDialogState, "Pozlama", s['exposure']!, -13, 0, (v) => s['exposure'] = v),
                  _slider(setDialogState, "Eşik", s['thresh']!, 5, 255, (v) => s['thresh'] = v),
                  _slider(setDialogState, "Zoom", s['zoom']!, 1, 8, (v) => s['zoom'] = v),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () { applyModeSettings(); Navigator.pop(context); }, child: const Text("KAYDET")),
            ],
          );
        },
      ),
    );
  }

  Widget _slider(StateSetter setDialogState, String label, double val, double min, double max, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label: ${val.toStringAsFixed(1)}", style: const TextStyle(fontSize: 10)),
        Slider(value: val, min: min, max: max, onChanged: (v) { setDialogState(() => onChanged(v)); }),
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
    // Koordinat eşleme: Yatay modda genişlik ve yükseklik yer değiştirir
    final double scaleX = size.width / previewSize.height;
    final double scaleY = size.height / previewSize.width;
    final Offset mappedPos = Offset(pos.dx * scaleX, pos.dy * scaleY);

    final paint = Paint()
      ..color = const Color(0xFF00FF00)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(mappedPos, 12, paint);
    canvas.drawLine(Offset(mappedPos.dx - 18, mappedPos.dy), Offset(mappedPos.dx + 18, mappedPos.dy), paint);
    canvas.drawLine(Offset(mappedPos.dx, mappedPos.dy - 18), Offset(mappedPos.dx, mappedPos.dy + 18), paint);
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}