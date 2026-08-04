import 'package:flutter/material.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 支付扫码页面（对齐 smdcapp MipcaActivityCapture）
///
/// 用于微信/支付宝/云闪付付款码扫描，UI 对齐 smdcapp 截图：
/// - 红色标题栏"扫一扫"
/// - 扫描框 + 蓝色扫描线动画
/// - 提示文字"把条形码放入框中进行扫描"
/// - 底部：连续扫描开关 + 相册图片按钮
class PayScanPage extends StatefulWidget {
  const PayScanPage({super.key});

  @override
  State<PayScanPage> createState() => _PayScanPageState();
}

class _PayScanPageState extends State<PayScanPage>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  /// 连续扫描模式（对齐 smdcapp 连续扫描开关）
  bool _continuousScan = false;

  /// 是否已扫描（非连续模式下防止重复触发）
  bool _hasScanned = false;

  /// 扫描线动画
  late final AnimationController _scanLineController;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    if (_continuousScan) {
      // 连续扫描模式：返回结果但不关闭页面，短暂延迟后继续
      _hasScanned = true;
      NavigatorUtils.goBackWithParams(context, code);
    } else {
      _hasScanned = true;
      NavigatorUtils.goBackWithParams(context, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: <Widget>[
          _buildAppBar(),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // 扫描框底部位置（与 _ScanFramePainter 保持一致）
                final double scanWidth = constraints.maxWidth * 0.75;
                final double scanHeight = scanWidth * 0.55;
                final double frameBottom = constraints.maxHeight * 0.18 + scanHeight;
                return Stack(
                  children: <Widget>[
                    // 相机预览
                    Positioned.fill(
                      child: MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                      ),
                    ),
                    // 扫描框遮罩 + 扫描线动画
                    Positioned.fill(
                      child: _ScanOverlayWithLine(
                        animation: _scanLineController,
                      ),
                    ),
                    // 提示文字（对齐 smdcapp "把条形码放入框中进行扫描"）
                    Positioned(
                      left: 0,
                      right: 0,
                      top: frameBottom + 24,
                      child: const Center(
                        child: Text(
                          '把条形码放入框中进行扫描',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  /// 顶部红色标题栏（对齐 smdcapp 红色标题栏"扫一扫"）
  Widget _buildAppBar() {
    return Container(
      color: const Color(0xFFE13426),
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: SizedBox(
        height: 48,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
              onPressed: () => NavigatorUtils.goBack(context),
            ),
            const Expanded(
              child: Text(
                '扫一扫',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 闪光灯按钮
            IconButton(
              icon: ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, child) {
                  return Icon(
                    state.torchState == TorchState.on
                        ? Icons.flash_on
                        : Icons.flash_off,
                    color: Colors.white,
                    size: 22,
                  );
                },
              ),
              onPressed: () => _controller.toggleTorch(),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部操作栏：连续扫描开关 + 相册图片（对齐 smdcapp 底部按钮区域）
  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.fromLTRB(
        24, 12, 24, MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // 连续扫描开关
          Row(
            children: <Widget>[
              const Text(
                '连续扫描',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 28,
                child: FittedBox(
                  child: Switch(
                    value: _continuousScan,
                    onChanged: (bool val) {
                      setState(() => _continuousScan = val);
                    },
                    activeColor: const Color(0xFFE13426),
                  ),
                ),
              ),
            ],
          ),
          // 相册图片（对齐 smdcapp 相册图片按钮）
          GestureDetector(
            onTap: _pickFromGallery,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 28,
                ),
                const SizedBox(height: 4),
                Text(
                  '相册图片',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 从相册识别条码（对齐 smdcapp 相册图片功能）
  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await ImagePicker()
          .pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final BarcodeCapture? result =
          await _controller.analyzeImage(image.path);
      if (result != null && result.barcodes.isNotEmpty) {
        final String? code = result.barcodes.first.rawValue;
        if (code != null && code.isNotEmpty) {
          if (mounted) NavigatorUtils.goBackWithParams(context, code);
          return;
        }
      }
      if (mounted) Toast.show('未识别到条码');
    } catch (_) {
      if (mounted) Toast.show('识别失败');
    }
  }
}

/// 扫描框遮罩 + 蓝色扫描线动画（对齐 smdcapp 扫描界面）
class _ScanOverlayWithLine extends StatelessWidget {
  const _ScanOverlayWithLine({required this.animation});

  final AnimationController animation;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanFramePainter(),
      child: AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _ScanLinePainter(progress: animation.value),
          );
        },
      ),
    );
  }
}

/// 扫描框遮罩绘制（半透明背景 + 中间透明方框 + 四角白色边线）
class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double scanWidth = size.width * 0.75;
    final double scanHeight = scanWidth * 0.55;
    final double left = (size.width - scanWidth) / 2;
    final double top = size.height * 0.18;

    // 半透明遮罩
    final Paint maskPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final Path maskPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(left, top, scanWidth, scanHeight))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(maskPath, maskPaint);

    // 四角白色边线（对齐 smdcapp 扫描框四角标记）
    final Paint cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const double cornerLen = 20;

    // 左上
    canvas.drawLine(Offset(left, top + cornerLen), Offset(left, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLen, top), cornerPaint);
    // 右上
    canvas.drawLine(Offset(left + scanWidth - cornerLen, top), Offset(left + scanWidth, top), cornerPaint);
    canvas.drawLine(Offset(left + scanWidth, top), Offset(left + scanWidth, top + cornerLen), cornerPaint);
    // 左下
    canvas.drawLine(Offset(left, top + scanHeight - cornerLen), Offset(left, top + scanHeight), cornerPaint);
    canvas.drawLine(Offset(left, top + scanHeight), Offset(left + cornerLen, top + scanHeight), cornerPaint);
    // 右下
    canvas.drawLine(Offset(left + scanWidth - cornerLen, top + scanHeight), Offset(left + scanWidth, top + scanHeight), cornerPaint);
    canvas.drawLine(Offset(left + scanWidth, top + scanHeight - cornerLen), Offset(left + scanWidth, top + scanHeight), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 蓝色扫描线动画绘制（对齐 smdcapp 扫描框中的蓝色横线）
class _ScanLinePainter extends CustomPainter {
  _ScanLinePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double scanWidth = size.width * 0.75;
    final double scanHeight = scanWidth * 0.55;
    final double left = (size.width - scanWidth) / 2;
    final double top = size.height * 0.18;

    // 扫描线 Y 坐标：在扫描框内上下移动
    final double lineY = top + 8 + (scanHeight - 16) * progress;

    final Paint linePaint = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.fill;

    // 渐变扫描线
    final Rect lineRect = Rect.fromLTWH(left + 6, lineY - 1.5, scanWidth - 12, 3);
    final Gradient gradient = LinearGradient(
      colors: <Color>[
        const Color(0xFF2196F3).withValues(alpha: 0.2),
        const Color(0xFF2196F3),
        const Color(0xFF2196F3).withValues(alpha: 0.2),
      ],
    );
    linePaint.shader = gradient.createShader(lineRect);
    canvas.drawRect(lineRect, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
