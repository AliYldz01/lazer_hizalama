import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void main() async {
  // 1. Flutter motorunun bağlandığından emin oluyoruz
  WidgetsFlutterBinding.ensureInitialized();
  
  List<CameraDescription> cameras = [];
  try {
    // 2. Kameraları alırken hata oluşursa uygulamanın çökmesini engelliyoruz
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Kamera yükleme hatası: $e");
  }

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    // Eğer kamera listesi boşsa bile uygulama hata verip kapanmaz
    home: cameras.isEmpty 
        ? const Scaffold(body: Center(child: Text("Kamera bulunamadı!"))) 
        : LazerHizalamaApp(cameras: cameras),
  ));
}

class LazerHizalamaApp extends StatefulWidget {
  final List<CameraDescription> cameras;
  const LazerHizalamaApp({super.key, required this.cameras});

  @override
  State<LazerHizalamaApp> createState() => _LazerHizalamaAppState();
}

class _LazerHizalamaAppState extends State<LazerHizalamaApp> {
  CameraController? controller;
  Offset? lazerNoktasi;
  bool isAnalyzing = false; // Performans için kilit mekanizması

  @override
  void initState() {
    super.initState();
    // iOS için enableAudio: false olması önemlidir, mikrofon izni sormasını engeller
    controller = CameraController(
      widget.cameras[0], 
      ResolutionPreset.high, 
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888, // iOS için optimize edilmiş format
    );

    controller!.initialize().then((_) {
      if (!mounted) return;
      
      // startImageStream'i güvenli bir şekilde başlatıyoruz
      controller!.startImageStream((image) {
        if (!isAnalyzing) {
          isAnalyzing = true;
          analizEt(image);
          isAnalyzing = false;
        }
      });
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        debugPrint("Kamera Hatası: ${e.description}");
      }
    });
  }

  void analizEt(CameraImage image) {
    int maxParlaklik = 0;
    int tempX = 0;
    int tempY = 0;

    // Plane 0 (Y düzlemi) parlaklık verisini içerir
    final bytes = image.planes[0].bytes;
    
    // Performansı artırmak için tarama aralığını (+=4) koruduk
    for (int y = 0; y < image.height; y += 4) {
      for (int x = 0; x < image.width; x += 4) {
        int index = y * image.width + x;
        if (index < bytes.length && bytes[index] > maxParlaklik) {
          maxParlaklik = bytes[index];
          tempX = x; 
          tempY = y;
        }
      }
    }

    if (maxParlaklik > 245) {
      if (mounted) {
        setState(() {
          lazerNoktasi = Offset(tempX.toDouble(), tempY.toDouble());
        });
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(controller!),
          if (lazerNoktasi != null)
            CustomPaint(painter: LazerPainter(lazerNoktasi!)),
          Positioned(
            bottom: 40,
            width: MediaQuery.of(context).size.width,
            child: const Center(
              child: Text("Sistem Aktif", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}

class LazerPainter extends CustomPainter {
  final Offset pos;
  LazerPainter(this.pos);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    
    canvas.drawCircle(pos, 20, paint);
    canvas.drawLine(Offset(pos.dx - 30, pos.dy), Offset(pos.dx + 30, pos.dy), paint);
    canvas.drawLine(Offset(pos.dx, pos.dy - 30), Offset(pos.dx, pos.dy + 30), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}