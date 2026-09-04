import 'package:flutter/material.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 结算完成页（对齐 smdcapp SettleFinishActivity）
///
/// 结账成功后展示支付结果：实收金额、找零、支付方式，
/// 点击完成返回桌台首页。
class SettleFinishPage extends StatelessWidget {
  const SettleFinishPage({
    super.key,
    this.tableName = '',
    this.payAmt = 0,
    this.receivedAmt = 0,
    this.changeAmt = 0,
    this.payName = '',
    this.takecode = '',
  });

  final String tableName;

  /// 应收金额
  final double payAmt;

  /// 实收金额
  final double receivedAmt;

  /// 找零金额
  final double changeAmt;

  /// 支付方式名称
  final String payName;

  /// 取餐号（对齐 smdcapp TakeSnackcode，快餐模式叫号）
  final String takecode;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _finish(context);
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6F8),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              const SizedBox(height: 60),
              // 成功图标
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, size: 56, color: Colors.green),
              ),
              const SizedBox(height: 20),
              const Text(
                '结账成功',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1D2129)),
              ),
              // 取餐号（对齐 smdcapp 快餐模式叫号 TakeSnackcode）
              if (takecode.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '取餐号：$takecode',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFF9800)),
                    ),
                  ),
                ),
              if (tableName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tableName,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF86909C)),
                  ),
                ),
              const SizedBox(height: 30),
              // 金额信息卡片
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Column(
                  children: <Widget>[
                    _infoRow('应收金额', '¥${payAmt.toStringAsFixed(2)}'),
                    const Divider(height: 20),
                    _infoRow('实收金额', '¥${receivedAmt.toStringAsFixed(2)}', highlight: true),
                    if (changeAmt > 0) ...<Widget>[
                      const Divider(height: 20),
                      _infoRow('找零', '¥${changeAmt.toStringAsFixed(2)}'),
                    ],
                    if (payName.isNotEmpty) ...<Widget>[
                      const Divider(height: 20),
                      _infoRow('支付方式', payName),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              // 完成按钮
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _finish(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBrandRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('完成', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF86909C))),
        Text(
          value,
          style: TextStyle(
            fontSize: highlight ? 20 : 15,
            fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
            color: highlight ? _kBrandRed : const Color(0xFF1D2129),
          ),
        ),
      ],
    );
  }

  /// 完成：刷新桌台并关闭所有结账流程页面返回首页
  /// （对齐 smdcapp SettleFinishActivity → post FinishSettlemEvent，
  /// 结算页/订单详情页/确认页等监听后 finish，最终回到 TableInfoActivity）
  void _finish(BuildContext context) {
    TableEventBus.fireTableChanged();
    NavigatorUtils.unfocus();
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }
}
