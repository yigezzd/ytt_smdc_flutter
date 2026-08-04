import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 语音播报服务（对齐 smdcapp SoudTipsUtils + VoiceTextTemplate + SoundPoolPlayV2）
///
/// 用于外卖新单、扫码点餐新单、退单等场景的语音提示。
/// 使用 flutter_tts 实现文字转语音播报。
///
/// 语音模板（对齐 smdcapp VoiceTextTemplate）：
/// - 新订单："您有新的外卖订单，请及时处理"
/// - 扫码点餐："您有新的扫码点餐订单"
/// - 退单："您有新的退单申请，请及时处理"
/// - 催单："顾客正在催单，请尽快处理"
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  FlutterTts? _tts;
  bool _initialized = false;

  /// 是否启用语音播报（对齐 smdcapp ConstantSetKey.TS_NEW_ORDER）
  bool enabled = true;

  /// 初始化 TTS 引擎
  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      _tts = FlutterTts();
      await _tts!.setLanguage('zh-CN');
      await _tts!.setSpeechRate(0.5);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
      _initialized = true;
      debugPrint('[VoiceService] TTS 初始化成功');
    } catch (e) {
      debugPrint('[VoiceService] TTS 初始化失败: $e');
    }
  }

  /// 播报文本
  Future<void> speak(String text) async {
    if (!enabled || _tts == null || !_initialized) return;
    try {
      await _tts!.speak(text);
      debugPrint('[VoiceService] 播报: $text');
    } catch (e) {
      debugPrint('[VoiceService] 播报失败: $e');
    }
  }

  /// 停止播报
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  // ──────────── 业务语音模板（对齐 smdcapp VoiceTextTemplate）─────────────────

  /// 外卖新订单播报（对齐 smdcapp TS_NEW_ORDER）
  Future<void> playNewTakeoutOrder({String platform = '外卖', double amount = 0}) async {
    final String amtText = amount > 0 ? '，金额${amount.toStringAsFixed(2)}元' : '';
    await speak('您有新的$platform订单$amtText，请及时处理');
  }

  /// 扫码点餐新订单播报
  Future<void> playNewScanOrder() async {
    await speak('您有新的扫码点餐订单，请及时处理');
  }

  /// 退单申请播报
  Future<void> playRefundApply() async {
    await speak('您有新的退单申请，请及时处理');
  }

  /// 催单播报
  Future<void> playUrgeOrder() async {
    await speak('顾客正在催单，请尽快处理');
  }

  /// 收款播报（对齐 smdcapp 收款语音）
  Future<void> playPaymentReceived(double amount) async {
    await speak('收款${amount.toStringAsFixed(2)}元');
  }

  /// 金额转中文大写播报（对齐 smdcapp genReadableMoney）
  static String amountToChinese(double amount) {
    const List<String> cnNums = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    const List<String> cnUnits = ['', '十', '百', '千', '万', '十', '百', '千', '亿'];

    final int integerPart = amount.floor();
    final int decimalPart = ((amount - integerPart) * 100).round();

    final StringBuffer sb = StringBuffer();

    // 整数部分
    if (integerPart == 0) {
      sb.write('零');
    } else {
      final String intStr = integerPart.toString();
      for (int i = 0; i < intStr.length; i++) {
        final int digit = int.parse(intStr[i]);
        final int unitIndex = intStr.length - 1 - i;
        if (digit == 0) {
          if (sb.isNotEmpty && !sb.toString().endsWith('零')) {
            sb.write('零');
          }
        } else {
          sb.write(cnNums[digit]);
          sb.write(cnUnits[unitIndex]);
        }
      }
    }
    sb.write('元');

    // 小数部分
    if (decimalPart > 0) {
      final int jiao = decimalPart ~/ 10;
      final int fen = decimalPart % 10;
      if (jiao > 0) {
        sb.write(cnNums[jiao]);
        sb.write('角');
      }
      if (fen > 0) {
        sb.write(cnNums[fen]);
        sb.write('分');
      }
    } else {
      sb.write('整');
    }

    return sb.toString();
  }
}
