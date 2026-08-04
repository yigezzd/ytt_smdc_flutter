import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/mq_service.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';

/// 外卖订单页（对齐 smdcapp TakeoutHomeActivity）
///
/// 显示外卖平台（美团/饿了么/抖音等）推送的订单列表，
/// 支持接单、拒单、退单处理、催单回复、配送/送达操作。
class TakeoutPage extends StatefulWidget {
  const TakeoutPage({super.key});

  @override
  State<TakeoutPage> createState() => _TakeoutPageState();
}

class _TakeoutPageState extends State<TakeoutPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;

  /// 外卖订单列表
  List<Map<String, dynamic>> _orders = <Map<String, dynamic>>[];

  /// 当前选中的tab: 0=待处理 1=已完成 2=扫码点餐
  int _currentTab = 0;

  /// MQ 订阅（扫码点餐新单推送实时刷新，对齐 smdcapp WMEvent/SmOrderEvent）
  StreamSubscription<Map<String, dynamic>>? _scanOrderSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
        _loadOrders();
      }
    });
    _loadOrders();
    // 订阅扫码点餐新单 MQ 推送，自动刷新列表
    _scanOrderSub = MqService.instance.onScanOrder.listen((_) {
      if (mounted) {
        Toast.show('收到新的扫码点餐订单');
        _loadOrders();
      }
    });
  }

  @override
  void dispose() {
    _scanOrderSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ==================== 数据加载 ====================

  /// 加载外卖订单（对齐 smdcapp TakeOutApi.orderGetAll / queryFinishOrder / apporder.getOrderList）
  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> resp;
      if (_currentTab == 2) {
        // 扫码点餐订单（对齐 smdcapp apporder/getOrderList）
        resp = await requestForm(HttpApi.appOrderGetList, <String, dynamic>{
          'page': '1',
          'pagesize': '50',
          'is_page': '0',
          'orderstatus': '1', // 待接单
          'field': 'id',
          'type': 'desc',
        }, showError: false);
      } else {
        final String url = _currentTab == 0
            ? HttpApi.wmOrderGetAll
            : HttpApi.wmQueryFinishOrder;
        resp = await requestForm(url, <String, dynamic>{
          'data': jsonEncode(<String, dynamic>{
            'page': 1,
            'pagesize': 50,
          }),
        }, showError: false);
      }
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is List) {
        _orders = data.whereType<Map<String, dynamic>>().toList();
      } else if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          _orders = list.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (_) {
      _orders = <Map<String, dynamic>>[];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 扫码点餐接单（对齐 smdcapp saleapporder/updateOrderStatus）
  Future<void> _acceptScanOrder(Map<String, dynamic> order) async {
    final bool confirmed = await ConfirmDialog.show(context, content: '确定接受该扫码点餐订单？');
    if (!confirmed || !mounted) return;
    try {
      await requestForm(HttpApi.updateOrderStatus, <String, dynamic>{
        'billno': order['billno']?.toString() ?? '',
        'ordertype': '2', // 接单
      });
      Toast.show('接单成功');
      _loadOrders();
    } catch (_) {
      Toast.show('接单失败');
    }
  }

  /// 扫码点餐取消（对齐 smdcapp apporder/cancelOrder）
  Future<void> _cancelScanOrder(Map<String, dynamic> order) async {
    final bool confirmed = await ConfirmDialog.show(context, content: '确定取消该扫码点餐订单？');
    if (!confirmed || !mounted) return;
    try {
      await requestForm(HttpApi.appOrderCancel, <String, dynamic>{
        'billno': order['billno']?.toString() ?? '',
      });
      Toast.show('已取消');
      _loadOrders();
    } catch (_) {
      Toast.show('操作失败');
    }
  }

  // ==================== 操作 ====================

  /// 接单（对齐 smdcapp TakeOutApi.orderConfirm）
  Future<void> _confirmOrder(Map<String, dynamic> order) async {
    final bool confirmed = await ConfirmDialog.show(context, content: '确定接受该外卖订单？');
    if (!confirmed || !mounted) return;
    try {
      await requestForm(HttpApi.wmOrderConfirm, <String, dynamic>{
        'data': jsonEncode(order),
      });
      Toast.show('接单成功');
      _loadOrders();
    } catch (_) {
      Toast.show('接单失败');
    }
  }

  /// 拒单（对齐 smdcapp TakeOutApi.orderCancel）
  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final bool confirmed = await ConfirmDialog.show(context, content: '确定拒绝该外卖订单？');
    if (!confirmed || !mounted) return;
    try {
      await requestForm(HttpApi.wmOrderCancel, <String, dynamic>{
        'data': jsonEncode(order),
      });
      Toast.show('已拒单');
      _loadOrders();
    } catch (_) {
      Toast.show('操作失败');
    }
  }

  /// 同意退单（对齐 smdcapp TakeOutApi.orderRefundAgree）
  Future<void> _refundAgree(Map<String, dynamic> order) async {
    final bool confirmed = await ConfirmDialog.show(context, content: '确定同意退单？');
    if (!confirmed || !mounted) return;
    try {
      await requestForm(HttpApi.wmOrderRefundAgree, <String, dynamic>{
        'data': jsonEncode(order),
      });
      Toast.show('已同意退单');
      _loadOrders();
    } catch (_) {
      Toast.show('操作失败');
    }
  }

  /// 配送（对齐 smdcapp TakeOutApi.orderDeliver）
  Future<void> _deliverOrder(Map<String, dynamic> order) async {
    try {
      await requestForm(HttpApi.wmOrderDeliver, <String, dynamic>{
        'data': jsonEncode(order),
      });
      Toast.show('已标记配送');
      _loadOrders();
    } catch (_) {
      Toast.show('操作失败');
    }
  }

  /// 送达（对齐 smdcapp TakeOutApi.orderReceived）
  Future<void> _receivedOrder(Map<String, dynamic> order) async {
    try {
      await requestForm(HttpApi.wmOrderReceived, <String, dynamic>{
        'data': jsonEncode(order),
      });
      Toast.show('已标记送达');
      _loadOrders();
    } catch (_) {
      Toast.show('操作失败');
    }
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: const MyAppBar(centerTitle: '外卖订单'),
      body: Column(
        children: <Widget>[
          // Tab栏
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFE13426),
              unselectedLabelColor: const Color(0xFF666666),
              indicatorColor: const Color(0xFFE13426),
              tabs: const <Widget>[
                Tab(text: '待处理'),
                Tab(text: '已完成'),
                Tab(text: '扫码点餐'),
              ],
            ),
          ),
          // 订单列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _orders.isEmpty
                    ? const Center(
                        child: Text('暂无外卖订单', style: TextStyle(color: Color(0xFF999999))),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _orders.length,
                          itemBuilder: (BuildContext ctx, int i) => _buildOrderCard(_orders[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final String orderNo = order['orderno']?.toString() ?? order['billno']?.toString() ?? '';
    final String platform = order['platform']?.toString() ?? order['source']?.toString() ?? '外卖';
    final String status = order['orderstatus']?.toString() ?? '';
    final String amt = order['amt']?.toString() ?? order['totalamt']?.toString() ?? '0';
    final String address = order['address']?.toString() ?? '';
    final String phone = order['phone']?.toString() ?? order['mobile']?.toString() ?? '';
    final String remark = order['remark']?.toString() ?? order['memo']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 头部：平台 + 状态
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(platform, style: const TextStyle(fontSize: 11, color: Color(0xFFFF9800))),
              ),
              const Spacer(),
              Text(_statusText(status), style: TextStyle(fontSize: 12, color: _statusColor(status))),
            ],
          ),
          const SizedBox(height: 8),
          // 订单号 + 金额
          Row(
            children: <Widget>[
              Expanded(
                child: Text('订单号：$orderNo', style: const TextStyle(fontSize: 13, color: Color(0xFF333333))),
              ),
              Text('¥$amt', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFE13426))),
            ],
          ),
          if (address.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text('地址：$address', style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
          ],
          if (phone.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text('电话：$phone', style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
          ],
          if (remark.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text('备注：$remark', style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
          ],
          const SizedBox(height: 10),
          // 操作按钮
          _buildActionButtons(order, status),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> order, String status) {
    final List<Widget> buttons = <Widget>[];
    // 扫码点餐tab：显示接单/取消按钮
    if (_currentTab == 2) {
      buttons.add(_actionBtn('接单', Colors.green, () => _acceptScanOrder(order)));
      buttons.add(_actionBtn('取消', Colors.red, () => _cancelScanOrder(order)));
      return Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons);
    }
    // 对齐 smdcapp: 根据订单状态显示不同操作按钮
    switch (status) {
      case '0': // 待接单
        buttons.add(_actionBtn('接单', Colors.green, () => _confirmOrder(order)));
        buttons.add(_actionBtn('拒单', Colors.red, () => _cancelOrder(order)));
        break;
      case '2': // 已接单/制作中
        buttons.add(_actionBtn('配送', Colors.blue, () => _deliverOrder(order)));
        break;
      case '3': // 配送中
        buttons.add(_actionBtn('送达', Colors.orange, () => _receivedOrder(order)));
        break;
      case '5': // 退单申请
        buttons.add(_actionBtn('同意退单', Colors.red, () => _refundAgree(order)));
        break;
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: buttons,
    );
  }

  Widget _actionBtn(String text, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          textStyle: const TextStyle(fontSize: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(text),
      ),
    );
  }

  String _statusText(String status) {
    switch (status) {
      case '0': return '待接单';
      case '1': return '待取餐';
      case '2': return '制作中';
      case '3': return '配送中';
      case '4': return '已完成';
      case '5': return '退单申请';
      case '10': return '已取消';
      default: return '未知';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case '0': return Colors.orange;
      case '4': return Colors.green;
      case '5': return Colors.red;
      case '10': return Colors.grey;
      default: return const Color(0xFF333333);
    }
  }
}
