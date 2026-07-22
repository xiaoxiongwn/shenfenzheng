import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '身份证A4排版打印',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _frontImage;
  File? _backImage;
  bool _isVertical = true;
  bool _isProcessing = false;
  
  double _gapPixels = 300.0; 

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAndCropImage(bool isFront, ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 100);
    if (pickedFile == null) return;

    // 调起裁剪界面，解除比例锁定，支持自由长宽缩放
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '自由裁剪身份证',
          toolbarColor: Colors.blue,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: false, // 允许自由调整长宽
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: '自由裁剪身份证',
          aspectRatioLockEnabled: false, // 允许自由调整长宽
          resetAspectRatioEnabled: true,
        ),
      ],
    );

    if (croppedFile != null) {
      setState(() {
        if (isFront) {
          _frontImage = File(croppedFile.path);
        } else {
          _backImage = File(croppedFile.path);
        }
      });
    }
  }

  // 给图片添加透明圆角
  img.Image applyRoundedCorners(img.Image src, int radius) {
    img.Image dst = img.Image(width: src.width, height: src.height, numChannels: 4);
    img.compositeImage(dst, src); // 复制原图并添加Alpha通道

    int w = src.width;
    int h = src.height;
    int r2 = (radius - 1) * (radius - 1);

    // 四个角变透明
    for (int y = 0; y < radius; y++) {
      for (int x = 0; x < radius; x++) {
        int dx = x - (radius - 1);
        int dy = y - (radius - 1);
        if (dx * dx + dy * dy > r2) {
          dst.setPixelRgba(x, y, 0, 0, 0, 0); // 左上
          dst.setPixelRgba(w - 1 - x, y, 0, 0, 0, 0); // 右上
          dst.setPixelRgba(x, h - 1 - y, 0, 0, 0, 0); // 左下
          dst.setPixelRgba(w - 1 - x, h - 1 - y, 0, 0, 0, 0); // 右下
        }
      }
    }
    return dst;
  }

  Future<void> _generateAndShare() async {
    if (_frontImage == null || _backImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择或拍摄身份证正反面照片')),
      );
      return;
    }

    setState(() { _isProcessing = true; });

    try {
      final frontBytes = await _frontImage!.readAsBytes();
      final backBytes = await _backImage!.readAsBytes();
      final frontImg = img.decodeImage(frontBytes)!;
      final backImg = img.decodeImage(backBytes)!;

      // 强制缩放为标准尺寸
      final resizedFront = img.copyResize(frontImg, width: 1011, height: 638);
      final resizedBack = img.copyResize(backImg, width: 1011, height: 638);

      // 添加圆角 (35px 约等于实际身份证 3mm 圆角)
      final roundedFront = applyRoundedCorners(resizedFront, 35);
      final roundedBack = applyRoundedCorners(resizedBack, 35);

      // 创建 A4 画布
      final canvas = img.Image(width: 2480, height: 3508);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

      int gap = _gapPixels.toInt();

      if (_isVertical) {
        int totalH = 638 * 2 + gap;
        int y1 = (3508 - totalH) ~/ 2;
        int y2 = y1 + 638 + gap;
        int x = (2480 - 1011) ~/ 2;
        img.compositeImage(canvas, roundedFront, dstX: x, dstY: y1);
        img.compositeImage(canvas, roundedBack, dstX: x, dstY: y2);
      } else {
        int totalW = 1011 * 2 + gap;
        int x1 = (2480 - totalW) ~/ 2;
        int x2 = x1 + 1011 + gap;
        int y = (3508 - 638) ~/ 2;
        img.compositeImage(canvas, roundedFront, dstX: x1, dstY: y);
        img.compositeImage(canvas, roundedBack, dstX: x2, dstY: y);
      }

      final pngBytes = img.encodePng(canvas);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/身份证A4排版_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles([XFile(file.path)], text: '身份证A4排版已生成，请打印');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败: $e')),
      );
    } finally {
      setState(() { _isProcessing = false; });
    }
  }

  Widget _buildImageSelector(String title, File? imageFile, bool isFront) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 200,
              color: Colors.grey[200],
              child: imageFile != null
                  ? Image.file(imageFile, fit: BoxFit.contain)
                  : const Center(child: Text('未选择图片', style: TextStyle(color: Colors.grey))),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.photo),
                  label: const Text('相册'),
                  onPressed: () => _pickAndCropImage(isFront, ImageSource.gallery),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('拍照'),
                  onPressed: () => _pickAndCropImage(isFront, ImageSource.camera),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double gapMm = _gapPixels / 300 * 25.4;

    return Scaffold(
      appBar: AppBar(title: const Text('身份证A4排版打印')),
      body: _isProcessing
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('正在生成高清A4图片...', style: TextStyle(fontSize: 16)),
              ],
            ))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildImageSelector('身份证正面 (人像面)', _frontImage, true),
                  const SizedBox(height: 16),
                  _buildImageSelector('身份证反面 (国徽面)', _backImage, false),
                  const SizedBox(height: 24),
                  const Text('选择排版方式：', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('竖向排列'),
                          value: true,
                          groupValue: _isVertical,
                          onChanged: (value) => setState(() => _isVertical = value!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('横向排列'),
                          value: false,
                          groupValue: _isVertical,
                          onChanged: (value) => setState(() => _isVertical = value!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('正反面间距：${gapMm.toStringAsFixed(1)} mm', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _gapPixels,
                    min: 0,
                    max: 800,
                    divisions: 80,
                    label: gapMm.toStringAsFixed(1),
                    onChanged: (value) => setState(() => _gapPixels = value),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _generateAndShare,
                    child: const Text('生成A4图片并分享打印', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '说明：选图或拍照后可自由拖动边框进行裁剪。生成图片时将自动为四个角添加圆弧效果，并缩放为身份证原件大小。打印时请选择“实际大小”。',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  )
                ],
              ),
            ),
    );
  }
}
