import 'package:flutter/material.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 结算完成页（对齐 smdcapp SettleFinishActivity）
///
/// 结账成功后展示订单明细：共X份/应收、实收/找零、订单号、收银员、
/// 支付方式、支付时间，点击完成返回桌台首页。
class SettleFinishPage extends StatelessWidget {
  const SettleFinishPage({
    super.key,
    this.tableName = '',
    this.payAmt = 0,
    this.receivedAmt = 0,
    this.changeAmt = 0,
    this.payName = '',
    this.takecode = '',
    this.billno = '',
    this.billdate = '',
    this.detailCount = 0,
    this.cashierName = '',
  });

  final String tableName;

  /// 应收金额
  final double payAmt;

  /// 实收金额（对齐 smdcapp t_sale_master.payment，不含抹零）
  final double receivedAmt;

  /// 找零金额（对齐 smdcapp t_sale_master.changeamt）
  final double changeAmt;

  /// 支付方式名称（多条支付方式以 / 拼接，对齐 smdcapp t_sale_payway）
  final String payName;

  /// 取餐号（对齐 smdcapp TakeSnackcode，快餐模式叫号）
  final String takecode;

  /// 订单号（对齐 smdcapp SaleBean.billno）
  final String billno;

  /// 支付时间（对齐 smdcapp t_sale_master.billdate）
  final String billdate;

  /// 明细份数（对齐 smdcapp t_sale_detail.size）
  final int detailCount;

  /// 收银员（对齐 smdcapp：有桌台取服务员，否则取当前登录人）
  final String cashierName;

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
              // 桌台号（对齐 smdcapp：桌台图标 + 桌台名；快餐叫号时隐藏，避免与取餐号混淆）
              if (tableName.isNotEmpty && takecode.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          'assets/images/icon_table.png',
                          width: 18,
                          height: 18,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        tableName,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF86909C)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              // 订单明细卡片（对齐 smdcapp SettleFinishActivity 订单明细区）
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Column(
                  children: <Widget>[
                    // 头部：红竖条 + 订单明细 + 共X份,应收
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 3,
                            height: 14,
                            decoration: BoxDecoration(
                              color: _kBrandRed,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Text(
                            '订单明细',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1D2129),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '共$detailCount份,应收：¥${payAmt.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF1D2129)),
                          ),
                        ],
                      ),
                    ),
                    _divider(),
                    // 实收 / 找零（对齐 smdcapp：找零金额红色）
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: <Widget>[
                          Text(
                            '实收：¥${receivedAmt.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF1D2129)),
                          ),
                          const Spacer(),
                          const Text('找零：', style: TextStyle(fontSize: 14, color: Color(0xFF1D2129))),
                          Text(
                            '¥${changeAmt.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, color: _kBrandRed),
                          ),
                        ],
                      ),
                    ),
                    _divider(),
                    _infoRow('订单号：', billno),
                    _divider(),
                    _infoRow('收银员：', cashierName),
                    _divider(),
                    _infoRow('支付方式：', payName),
                    _divider(),
                    _infoRow('支付时间：', billdate),
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

  Widget _divider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFFEFEFEF),
    );
  }

  /// 标签 + 右对齐值（对齐 smdcapp SettleFinishActivity 明细行）
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF86909C))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: Color(0xFF1D2129)),
            ),
          ),
        ],
      ),
    );
  }

  /// 完成：刷新桌台并关闭所有结账流程页面
  ///
  /// 对齐 smdcapp SettleFinishActivity.finishView：
  /// - 快餐模式（storemodel==1）：重新进入点菜页开新单（重置 saleid，避免二次下单串单）；
  /// - 正餐模式：回到桌台首页。
  void _finish(BuildContext context) {
    TableEventBus.fireTableChanged();
    NavigatorUtils.unfocus();
    final NavigatorState navigator = Navigator.of(context);
    navigator.popUntil((Route<dynamic> route) => route.isFirst);
    if (StoreModeUtils.isFastMode()) {
      NavigatorUtils.push(
        navigator.context,
        Routes.orderPage,
        arguments: <String, dynamic>{
          'fastMode': true,
          'saleid': StoreModeUtils.generateSaleId(),
        },
      );
    }
  }
}
