import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  bool _isVertical = true; // 默认竖向排列
  bool _isProcessing = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(bool isFront, ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 100);
    if (pickedFile != null) {
      setState(() {
        if (isFront) {
          _frontImage = File(pickedFile.path);
        } else {
          _backImage = File(pickedFile.path);
        }
      });
    }
  }

  Future<void> _generateAndShare() async {
    if (_frontImage == null || _backImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择或拍摄身份证正反面照片')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // 1. 读取并解码图片
      final frontBytes = await _frontImage!.readAsBytes();
      final backBytes = await _backImage!.readAsBytes();
      final frontImg = img.decodeImage(frontBytes)!;
      final backImg = img.decodeImage(backBytes)!;

      // 2. 调整为身份证真实大小 (300 DPI 打印标准)
      // 身份证尺寸：长 85.6mm (1011px), 宽 54.0mm (638px)
      final resizedFront = img.copyResize(frontImg, width: 1011, height: 638);
      final resizedBack = img.copyResize(backImg, width: 1011, height: 638);

      // 3. 创建 A4 纸画布 (300 DPI: 210mm x 297mm -> 2480px x 3508px)
      final canvas = img.Image(width: 2480, height: 3508);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255)); // 白色背景

      // 4. 根据选择的方式进行排版
      if (_isVertical) {
        // 竖向排列：居中，正面在上，反面在下
        int x = (2480 - 1011) ~/ 2;
        int y1 = 400; // 距离顶部约 3.3cm
        int y2 = y1 + 638 + 300; // 间距约 2.5cm
        img.compositeImage(canvas, resizedFront, dstX: x, dstY: y1);
        img.compositeImage(canvas, resizedBack, dstX: x, dstY: y2);
      } else {
        // 横向排列：居中，正面在左，反面在右
        int y = (3508 - 638) ~/ 2;
        int x1 = 400; // 距离左侧约 3.3cm
        int x2 = x1 + 1011 + 300; // 间距约 2.5cm
        img.compositeImage(canvas, resizedFront, dstX: x1, dstY: y);
        img.compositeImage(canvas, resizedBack, dstX: x2, dstY: y);
      }

      // 5. 将画布编码为 PNG 图片
      final pngBytes = img.encodePng(canvas);

      // 6. 保存到手机临时目录
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/id_card_a4_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      // 7. 调用系统分享（可直接发给打印机或保存到相册）
      await Share.shareXFiles([XFile(file.path)], text: '身份证A4排版已生成，请打印');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败: $e')),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // 构建图片选择UI
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
                  onPressed: () => _pickImage(isFront, ImageSource.gallery),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('拍照'),
                  onPressed: () => _pickImage(isFront, ImageSource.camera),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('身份证A4排版打印'),
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('正在生成高清A4图片...', style: TextStyle(fontSize: 16)),
                ],
              ),
            )
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
                  const SizedBox(height: 24),
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
                    '说明：生成的图片为300DPI高清分辨率，尺寸已自动缩放为身份证原件大小(85.6mm × 54.0mm)。生成后可直接发送给连接打印机的应用进行打印。',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  )
                ],
              ),
            ),
    );
  }
}
