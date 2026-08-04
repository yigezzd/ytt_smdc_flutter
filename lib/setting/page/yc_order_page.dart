import 'package:flutter/material.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';

/// 异常订单查询页（对齐 smdcapp YcOrderActivity）
/// smdcapp 中此页面读取本地 Room 数据库 PayFlow 表，展示未上传/交易异常的流水。
/// Flutter 端暂无本地流水缓存机制，此页预留结构，后续对接本地存储。
class YcOrderPage extends StatefulWidget {
  const YcOrderPage({super.key});

  @override
  State<YcOrderPage> createState() => _YcOrderPageState();
}

class _YcOrderPageState extends State<YcOrderPage> {
  /// 异常订单列表（当前无本地数据库，预留）
  final List<Map<String, dynamic>> _orderList = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    // TODO: 对接本地流水数据库（对齐 smdcapp DbManager.db.getPayFlowDao()）
    // 当前 Flutter 端无本地 PayFlow 存储，显示空态
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black87),
          onPressed: () => NavigatorUtils.goBack(context),
        ),
        title: const Text(
          '异常订单',
          style: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: <Widget>[
          if (_orderList.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('全部清除', style: TextStyle(color: Color(0xFFE13426))),
            ),
        ],
      ),
      body: _orderList.isEmpty ? _buildEmpty() : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.check_circle_outline, size: 64, color: Color(0xFFCCCCCC)),
          SizedBox(height: 16),
          Text('暂无异常订单', style: TextStyle(fontSize: 15, color: Color(0xFF999999))),
          SizedBox(height: 8),
          Text('所有交易流水均已正常上传', style: TextStyle(fontSize: 13, color: Color(0xFFCCCCCC))),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _orderList.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final order = _orderList[index];
        return _buildOrderCard(order);
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final String billno = order['billno']?.toString() ?? '';
    final String tablename = order['tablename']?.toString() ?? '';
    final String amt = order['amt']?.toString() ?? '0';
    final String billdate = order['billdate']?.toString() ?? '';
    final String cashname = order['cashname']?.toString() ?? '';
    final String status = order['hasUploadFlag'] == '0' ? '流水未上传' : '交易异常';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status,
                  style: const TextStyle(fontSize: 11, color: Color(0xFFE13426)),
                ),
              ),
              const Spacer(),
              Text(billdate, style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
            ],
          ),
          const SizedBox(height: 10),
          Text('单号：$billno', style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
          const SizedBox(height: 4),
          if (tablename.isNotEmpty)
            Text(tablename, style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Text('¥$amt', style: const TextStyle(
                fontSize: 16, color: Color(0xFFE13426), fontWeight: FontWeight.bold,
              )),
              const Spacer(),
              Text('操作员：$cashname', style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
            ],
          ),
        ],
      ),
    );
  }

  void _clearAll() {
    setState(() => _orderList.clear());
  }
}
