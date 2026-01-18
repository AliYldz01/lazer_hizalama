import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:ui' as ui;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Uygulamayı donanım seviyesinde yatay modda kilitler
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
    'thresh': 245.0, 
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
      // iPhone 13 sensör oryantasyonunu yatay arayüzle eşitler
      await controller!.lockCaptureOrientation(DeviceOrientation.landscapeLeft);
      
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

    // iPhone 13 Yatay Mod Aranjmanı
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // EKRANIN %85'İ GÖRÜNTÜ ALANI (İKİLİ PANEL)
            Expanded(
              flex: 8, 
              child: Row(
                children: [
                  _buildWindow("CANLI AKIŞ: ${isLazerActive ? 'LAZER' : 'NOZZLE'}", 
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
                  
                  _buildWindow(
                    "REFERANS VE KARŞILAŞTIRMA", 
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        if (nozzlePhoto != null) RawImage(image: nozzlePhoto, fit: BoxFit.cover) 
                        else const Center(child: Text("Referans Fotoğrafı Yok", style: TextStyle(color: Colors.white54))),
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
            
            // EKRANIN %15'İ KONTROL PANELİ
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                color: const Color(0xFF1A1A1A),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _modeBtn("NOZZLE", !isLazerActive, Colors.blue, () {
                      setState(() => isLazerActive = false);
                      applyAllSettings();
                    }),
                    _modeBtn("LAZER", isLazerActive, Colors.redAccent, () {
                      setState(() => isLazerActive = true);
                      applyAllSettings();
                    }),
                    const VerticalDivider(color: Colors.white24, indent: 10, endIndent: 10),
                    _actionBtn("REFERANS ÇEK", Colors.green, captureNozzle),
                    const VerticalDivider(color: Colors.white24, indent: 10, endIndent: 10),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 30),
                      onPressed: _openSettings,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Pencere tasarımında başlıkların yatayda okunabilirliği için paddingler ayarlandı
  Widget _buildWindow(String title, Widget child, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
            Positioned(
              top: 0, left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: const BorderRadius.only(bottomRight: Radius.circular(8)),
                ),
                child: Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Butonlar yatay ekranın alt kısmına sığacak şekilde daraltıldı
  Widget _modeBtn(String txt, bool active, Color color, VoidCallback tap) {
    return SizedBox(
      height: 40,
      width: 100,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: active ? color : Colors.grey[900],
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: tap,
        child: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
      ),
    );
  }

  Widget _actionBtn(String txt, Color color, VoidCallback tap) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        onPressed: tap,
        icon: const Icon(Icons.camera_alt_outlined, size: 18),
        label: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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
            backgroundColor: const Color(0xFF1A1A1A),
            title: Text("${isLazerActive ? 'LAZER' : 'NOZZLE'} AYARLARI", style: const TextStyle(fontSize: 14)),
            content: SizedBox(
              width: 500, // Yatay ekranda diyalog genişletildi
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _slider(setDS, "POZLAMA", s['exposure']!, -10, 10, (v) => s['exposure'] = v),
                    _slider(setDS, "ODAK", s['focus']!, 0, 1, (v) => s['focus'] = v),
                    _slider(setDS, "EŞİK", s['thresh']!, 0, 255, (v) => s['thresh'] = v),
                    _slider(setDS, "ZOOM", s['zoom']!, 1, 10, (v) => s['zoom'] = v),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () { applyAllSettings(); Navigator.pop(context); }, child: const Text("UYGULA")),
            ],
          );
        },
      ),
    );
  }

  Widget _slider(StateSetter setDS, String lbl, double val, double min, double max, Function(double) change) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(lbl, style: const TextStyle(fontSize: 11)), Text(val.toStringAsFixed(1))],
        ),
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
    // IPHONE 13 LANDSCAPE FIX:
    // previewSize dikey (height > width) gelir. Ekran yatay (size.width > size.height).
    // Oranlamayı bu tersliğe göre yapıyoruz.
    final double scaleX = size.width / previewSize.height;
    final double scaleY = size.height / previewSize.width;
    
    final Offset mappedPos = Offset(pos.dx * scaleX, pos.dy * scaleY);

    final paint = Paint()..color = color..strokeWidth = 2..style = PaintingStyle.stroke;
    canvas.drawCircle(mappedPos, 15, paint);
    canvas.drawLine(Offset(mappedPos.dx - 30, mappedPos.dy), Offset(mappedPos.dx + 30, mappedPos.dy), paint);
    canvas.drawLine(Offset(mappedPos.dx, mappedPos.dy - 30), Offset(mappedPos.dx, mappedPos.dy + 30), paint);
    canvas.drawCircle(mappedPos, 2, paint..style = PaintingStyle.fill);
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}