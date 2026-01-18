import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: LazerHizalamaApp(cameras: cameras),
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

  @override
  void initState() {
    super.initState();
    controller = CameraController(widget.cameras[0], ResolutionPreset.high, enableAudio: false);
    controller!.initialize().then((_) {
      if (!mounted) return;
      controller!.startImageStream((image) => analizEt(image));
      setState(() {});
    });
  }

  void analizEt(CameraImage image) {
    int maxParlaklik = 0;
    int tempX = 0;
    int tempY = 0;

    final bytes = image.planes[0].bytes;
    for (int y = 0; y < image.height; y += 4) {
      for (int x = 0; x < image.width; x += 4) {
        int index = y * image.width + x;
        if (bytes[index] > maxParlaklik) {
          maxParlaklik = bytes[index];
          tempX = x; tempY = y;
        }
      }
    }

    if (maxParlaklik > 245) {
      setState(() {
        lazerNoktasi = Offset(tempX.toDouble(), tempY.toDouble());
      });
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