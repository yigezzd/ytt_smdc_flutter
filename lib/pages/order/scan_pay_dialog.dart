import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/pay_gateway.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 扫码支付弹窗（对齐 smdcapp DialogAliWechatPay + BoYouPayDialog/ReceiveMoneyPayDialog）
///
/// 展示支付金额，提交付款码到支付网关，轮询支付结果，60秒超时。
/// 返回 ScanPayResult（支付成功/失败结果）。
class ScanPayDialog extends StatefulWidget {
  const ScanPayDialog({
    super.key,
    required this.payid,
    required this.amt,
    required this.billNo,
    required this.authCode,
    required this.gateway,
  });

  /// 支付方式ID：08=支付宝 09=微信 10=云闪付
  final String payid;

  /// 支付金额（元）
  final double amt;

  /// 商户订单号（对齐 smdcapp lesBillNo = billNo + A + HHmmss）
  final String billNo;

  /// 客户付款码（扫描结果）
  final String authCode;

  /// 支付网关
  final PayGateway gateway;

  /// 弹出对话框并等待支付结果
  static Future<ScanPayResult?> show(
    BuildContext context, {
    required String payid,
    required double amt,
    required String billNo,
    required String authCode,
    required PayGateway gateway,
  }) {
    return showDialog<ScanPayResult>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return ScanPayDialog(
          payid: payid,
          amt: amt,
          billNo: billNo,
          authCode: authCode,
          gateway: gateway,
        );
      },
    );
  }

  @override
  State<ScanPayDialog> createState() => _ScanPayDialogState();
}

class _ScanPayDialogState extends State<ScanPayDialog> {
  /// 支付状态：0=处理中 1=失败（可重试/查询）
  int _state = 0;

  /// 倒计时秒数（对齐 smdcapp 60秒超时）
  int _countdown = 60;

  /// 错误/提示文本（对齐 smdcapp tvLoading）
  String _loadingText = '交易正在处理，请勿操作';

  /// 是否显示交易查询按钮（对齐 smdcapp btTradeQuery）
  bool _showTradeQuery = false;

  Timer? _countdownTimer;
  Timer? _pollTimer;
  bool _payFinished = false;
  bool _isPaying = false;

  @override
  void initState() {
    super.initState();
    _startPay();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// 发起支付（对齐 smdcapp clickSure → pay + timeTask + queryLeshua）
  Future<void> _startPay() async {
    if (_isPaying) return;
    _isPaying = true;

    setState(() {
      _state = 0;
      _showTradeQuery = false;
      _countdown = 60;
      _loadingText = '交易正在处理，请勿操作';
    });

    // 启动倒计时（对齐 smdcapp timeTask: 60秒超时，58秒提醒）
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdown--;
        _loadingText = '交易正在处理，请勿操作...${_countdown}s';
      });
      if (_countdown == 2 && !_payFinished) {
        // 对齐 smdcapp needCloseTrade: 58秒时提示
        Toast.show('支付即将超时，请提醒客户取消支付');
      }
      if (_countdown <= 0) {
        timer.cancel();
        _pollTimer?.cancel();
        // 对齐 smdcapp error() → closeOrder("支付超时", false)
        widget.gateway.closeOrder(widget.billNo);
        _finishPay(false, '支付超时');
      }
    });

    // 金额转分（对齐 smdcapp CalcUtils.multiplyV2(amt,100.0)）
    final int amtFen = (widget.amt * 100).round();

    try {
      final bool directSuccess = await widget.gateway.pay(
        payid: widget.payid,
        billNo: widget.billNo,
        amtFen: amtFen,
        authCode: widget.authCode,
      );

      if (!mounted) return;

      if (directSuccess) {
        // 直接支付成功（对齐 smdcapp handlerTradeSuccess → closeOrder(trade, true)）
        final String trade = widget.gateway.payType == '1'
            ? widget.gateway.sqbTradeNo
            : widget.gateway.boyouTrade;
        _finishPay(true, trade);
        return;
      }

      // 检查是否明确失败（对齐 smdcapp PAY_FAIL / status 6/8）
      final bool definitelyFailed = widget.gateway.payType == '1'
          ? widget.gateway.sqbPayDefinitelyFailed
          : widget.gateway.boyouPayDefinitelyFailed;
      if (definitelyFailed) {
        final String errMsg = widget.gateway.payType == '1'
            ? widget.gateway.sqbErrorMsg
            : widget.gateway.boyouErrorMsg;
        await widget.gateway.closeOrder(widget.billNo);
        if (mounted) _finishPay(false, errMsg);
        return;
      }

      // 非终态 → 开始轮询（对齐 smdcapp queryLeshua: 每2秒查询一次）
      _startPolling();
    } catch (_) {
      if (!mounted) return;
      // 网络异常 → 尝试查询（对齐 smdcapp onFailure → clickTrade）
      _startPolling();
    }
  }

  /// 轮询支付状态（对齐 smdcapp queryServer.scheduleAtFixedRate 每2秒）
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (Timer timer) async {
      if (_payFinished || !mounted) {
        timer.cancel();
        return;
      }
      try {
        final ScanPayResult result = await widget.gateway.queryStatus(
          billNo: widget.billNo,
          payid: widget.payid,
        );
        if (!mounted || _payFinished) {
          timer.cancel();
          return;
        }
        if (result.success) {
          timer.cancel();
          _finishPay(true, result.trade);
        } else if (result.trade.isNotEmpty) {
          // 明确失败（对齐 smdcapp closeOrder(error_msg, false)）
          timer.cancel();
          await widget.gateway.closeOrder(widget.billNo);
          if (mounted) _finishPay(false, result.trade);
        }
        // trade为空 → 非终态，继续轮询
      } catch (_) {
        // 查询异常继续轮询
      }
    });
  }

  /// 结束支付（对齐 smdcapp closeOrder）
  void _finishPay(bool success, String tradeOrError) {
    if (_payFinished) return;
    _payFinished = true;
    _countdownTimer?.cancel();
    _pollTimer?.cancel();

    if (success) {
      // 支付成功 → 关闭弹窗返回结果
      if (mounted) {
        Navigator.of(context).pop(ScanPayResult(
          success: true,
          trade: tradeOrError,
          payid: widget.payid,
          billNo: widget.billNo,
        ));
      }
    } else {
      // 支付失败 → 显示错误信息和查询按钮（对齐 smdcapp showPayCodeLayout(true)）
      if (mounted) {
        setState(() {
          _state = 1;
          _loadingText = tradeOrError.isNotEmpty ? tradeOrError : '支付失败';
          _showTradeQuery = true;
        });
      }
    }
  }

  /// 交易查询（对齐 smdcapp clickTrade：手动查询一次）
  Future<void> _onTradeQuery() async {
    try {
      final ScanPayResult result = await widget.gateway.queryStatus(
        billNo: widget.billNo,
        payid: widget.payid,
      );
      if (!mounted) return;
      if (result.success) {
        _finishPay(true, result.trade);
      } else if (result.trade.isNotEmpty) {
        setState(() {
          _loadingText = result.trade;
        });
      } else {
        setState(() {
          _loadingText = '查询异常';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingText = '查询异常';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 标题（对齐 smdcapp tvPayTitle: 08=支付宝支付 09=微信支付 else=云闪付支付）
    String title;
    Color titleColor;
    switch (widget.payid) {
      case '08':
        title = '支付宝支付';
        titleColor = const Color(0xFF1677FF);
        break;
      case '09':
        title = '微信支付';
        titleColor = const Color(0xFF07C160);
        break;
      default:
        title = '云闪付支付';
        titleColor = const Color(0xFFE6A23C);
    }

    return PopScope(
      canPop: _state == 1, // 支付中不允许返回（对齐 smdcapp setCancelable(false)）
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 标题
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 16),
              // 金额（对齐 smdcapp tvAmt）
              Text(
                '¥${widget.amt.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1D2129),
                ),
              ),
              const SizedBox(height: 20),
              // 状态区域（对齐 smdcapp rlLoading）
              if (_state == 0) ...<Widget>[
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 12),
                Text(
                  _loadingText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF86909C)),
                ),
              ] else ...<Widget>[
                // 失败状态（对齐 smdcapp showQueryTradeFail 布局）
                const Icon(Icons.error_outline, size: 36, color: Color(0xFFF56C6C)),
                const SizedBox(height: 10),
                Text(
                  _loadingText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFFF56C6C)),
                ),
                const SizedBox(height: 16),
                // 按钮区域（对齐 smdcapp btTradeQuery/btCancel/btSure）
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (_showTradeQuery)
                      _dialogBtn('交易查询', const Color(0xFF1677FF), _onTradeQuery),
                    if (_showTradeQuery) const SizedBox(width: 12),
                    _dialogBtn('关闭', const Color(0xFF86909C), () {
                      Navigator.of(context).pop(ScanPayResult(
                        success: false,
                        trade: _loadingText,
                        payid: widget.payid,
                        billNo: widget.billNo,
                        errorMsg: _loadingText,
                      ));
                    }),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogBtn(String text, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 14, color: color),
        ),
      ),
    );
  }
}
