import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';

/// 暂结订单页（对齐 smdcapp ZjOrderActivity）
///
/// 展示已暂结的订单列表，支持查看暂结详情、取消暂结、部分退款。
class ZanjieOrderPage extends StatefulWidget {
  const ZanjieOrderPage({super.key, this.saleid = ''});

  /// 指定桌台的 saleid（可选，为空则查全部）
  final String saleid;

  @override
  State<ZanjieOrderPage> createState() => _ZanjieOrderPageState();
}

class _ZanjieOrderPageState extends State<ZanjieOrderPage> {
  List<Map<String, dynamic>> _orders = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  /// 加载暂结订单列表（对齐 smdcapp getUpPayList / GetTableSalePayFornowList）
  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      final Map<String, dynamic> resp;
      if (useMaster) {
        resp = await requestForm(
          HttpApi.pcGetTableSalePayFornowList,
          <String, dynamic>{
            'data': jsonEncode(<String, dynamic>{
              'saleid': widget.saleid,
              'page': 1,
              'pagesize': 100,
            }),
          },
          masterDevice: true,
          showError: false,
        );
      } else {
        resp = await requestForm(
          HttpApi.getUpPayList,
          <String, dynamic>{
            'saleid': widget.saleid,
            'page': '1',
            'pagesize': '100',
          },
          showError: false,
        );
      }
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          _orders = list.whereType<Map<String, dynamic>>().toList();
        }
      } else if (data is List) {
        _orders = data.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {
      _orders = <Map<String, dynamic>>[];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 取消暂结（对齐 smdcapp updatePayInfo paystatus=2）
  Future<void> _cancelZanjie(Map<String, dynamic> order) async {
    final bool confirmed = await ConfirmDialog.show(context, content: '确定要取消暂结吗？');
    if (!confirmed || !mounted) return;
    try {
      await requestForm(HttpApi.updatePayInfo, <String, dynamic>{
        'saleid': order['saleid']?.toString() ?? widget.saleid,
        'fornowid': order['fornowid']?.toString() ?? order['id']?.toString() ?? '',
        'paystatus': '2',
      });
      if (!mounted) return;
      Toast.show('已取消暂结');
      TableEventBus.fireTableChanged();
      _loadOrders();
    } catch (_) {
      if (mounted) Toast.show('操作失败');
    }
  }

  /// 暂结退款（对齐 smdcapp refundPartPayInfo / ReturnFornow）
  Future<void> _refundZanjie(Map<String, dynamic> order) async {
    final bool confirmed = await ConfirmDialog.show(context, content: '确定要退还暂结款项吗？');
    if (!confirmed || !mounted) return;
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      final String saleid = order['saleid']?.toString() ?? widget.saleid;
      if (useMaster) {
        await requestForm(
          HttpApi.pcReturnFornow,
          <String, dynamic>{
            'data': jsonEncode(<String, dynamic>{
              'saleid': saleid,
              'fornowid': order['fornowid']?.toString() ?? order['id']?.toString() ?? '',
            }),
          },
          masterDevice: true,
        );
      } else {
        await requestForm(HttpApi.refundPartPayInfo, <String, dynamic>{
          'saleid': saleid,
          'payinfos': jsonEncode(<Map<String, dynamic>>[order]),
          'olddetaillist': '[]',
          'addlist': '[]',
        });
      }
      if (!mounted) return;
      Toast.show('退款成功');
      TableEventBus.fireTableChanged();
      _loadOrders();
    } catch (_) {
      if (mounted) Toast.show('退款失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: const MyAppBar(centerTitle: '暂结订单'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? const Center(child: Text('暂无暂结订单', style: TextStyle(color: Color(0xFF999999))))
              : RefreshIndicator(
                  onRefresh: _loadOrders,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _orders.length,
                    itemBuilder: (BuildContext ctx, int i) => _buildOrderCard(_orders[i]),
                  ),
                ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final String billno = order['billno']?.toString() ?? '';
    final String tablename = order['tablename']?.toString() ?? '';
    final String payamt = order['payamt']?.toString() ?? order['amt']?.toString() ?? '0';
    final String payname = order['payname']?.toString() ?? '';
    final String createtime = order['createtime']?.toString() ?? '';
    final int paystatus = int.tryParse(order['paystatus']?.toString() ?? '0') ?? 0;

    // 金额明细（对齐 smdcapp ZjOrderActivity 展示：菜品费/优惠/服务费/低消）
    final double cpAmt = _toDouble(order['cpAmt'] ?? order['amt'] ?? order['payamt']);
    final double dscAmt = _toDouble(order['dscamt']);
    final double serviceAmt = _toDouble(order['serviceamt']);
    final double lowAmt = _toDouble(order['lowamt']);
    final bool hasExtraFees = serviceAmt > 0 || lowAmt > 0;

    // 状态文字（对齐 smdcapp: 0=已退款, 1=部分退, 2=已付款）
    final String statusText = _getStatusText(paystatus);
    final Color statusColor = _getStatusColor(paystatus);

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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  tablename.isNotEmpty ? tablename : billno,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(fontSize: 11, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 金额明细行（对齐 smdcapp zj_order_itemv2）
          _buildAmtRow('菜品费', cpAmt),
          if (dscAmt > 0) _buildAmtRow('优惠金额', -dscAmt, color: Colors.green),
          if (hasExtraFees) ...<Widget>[
            if (serviceAmt > 0) _buildAmtRow('服务费', serviceAmt),
            if (lowAmt > 0) _buildAmtRow('低消', lowAmt),
          ],
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: Text('单号：$billno', style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
              ),
              Text('实收 ¥$payamt', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFE13426))),
            ],
          ),
          if (payname.isNotEmpty || createtime.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '$payname  $createtime',
              style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ],
          if (paystatus == 2) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => _cancelZanjie(order),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('取消暂结'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _refundZanjie(order),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE13426),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('退款'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 金额明细行
  Widget _buildAmtRow(String label, double value, {Color? color}) {
    final Color c = color ?? const Color(0xFF666666);
    final String text = value < 0 ? '-¥${value.abs().toStringAsFixed(2)}' : '¥${value.toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
          Text(text, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }

  /// 状态文字（对齐 smdcapp ZjOrderActivity paystatus 映射）
  String _getStatusText(int paystatus) {
    switch (paystatus) {
      case 0: return '已退款';
      case 1: return '部分退';
      case 2: return '已付款';
      default: return '暂结中';
    }
  }

  Color _getStatusColor(int paystatus) {
    switch (paystatus) {
      case 0: return Colors.grey;
      case 1: return Colors.orange;
      case 2: return Colors.green;
      default: return Colors.orange;
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
