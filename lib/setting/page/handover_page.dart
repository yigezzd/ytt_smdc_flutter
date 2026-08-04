import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 交接班页面（对齐 smdcapp HandWordActivity）
/// 流程：getMaxLogoutTime → reportOnShiftByMachno → 展示 → addShifthandover
class HandoverPage extends StatefulWidget {
  const HandoverPage({super.key});

  @override
  State<HandoverPage> createState() => _HandoverPageState();
}

class _HandoverPageState extends State<HandoverPage> {
  bool _loading = true;
  String _loginTime = '';
  String _logoutTime = '';

  // 交班汇总数据
  double _saleamt = 0;       // 收入金额
  double _payableamt = 0;    // 应交金额
  double _salecnt = 0;       // 总单数
  double _personnum = 0;     // 总人数
  double _perpersonprice = 0; // 人均消费
  double _serviceamt = 0;    // 服务费
  double _lowamt = 0;        // 低消差额
  double _amt = 0;           // 消费总额
  double _zfamt = 0;         // 支付金额
  double _zfcnt = 0;         // 支付笔数
  double _returncnt = 0;     // 退款笔数
  double _returnamt = 0;     // 退款金额

  // 支付方式列表
  List<Map<String, dynamic>> _payList = [];

  // 原始数据（用于提交交班）
  Map<String, dynamic>? _rawData;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // 1. 获取最后交班时间（对齐 smdcapp getMaxLogoutTime）
      final timeResult = await request(HttpApi.getMaxLogoutTime, null, false, false);
      final String maxTime = timeResult['data']?.toString() ?? '';
      _loginTime = maxTime.isNotEmpty ? maxTime : '${_today()} 00:00:00';

      // 2. 查询交班数据（对齐 smdcapp reportOnShiftByMachno）
      final String cashid = _getUserId();
      _logoutTime = _nowStr();
      final result = await requestForm(
        HttpApi.reportOnShift,
        <String, dynamic>{
          'cashid': cashid,
          'logintime': _loginTime,
          'logouttime': _logoutTime,
          'proflag': 1,
          'typeflag': 0,
          'retireflag': 1,
        },
      );
      final Map<String, dynamic>? data =
          result['data'] is Map ? Map<String, dynamic>.from(result['data'] as Map) : null;
      if (data != null) {
        _rawData = data;
        _parseData(data);
      }
    } catch (e) {
      if (mounted) {
        Toast.show('获取交班数据失败');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _parseData(Map<String, dynamic> data) {
    final Map<String, dynamic> sumdata =
        data['sumdata'] is Map ? Map<String, dynamic>.from(data['sumdata'] as Map) : <String, dynamic>{};
    _saleamt = _toDouble(sumdata['saleamt']);
    _payableamt = _toDouble(sumdata['payableamt']);
    _salecnt = _toDouble(sumdata['salecnt']);
    _personnum = _toDouble(sumdata['personnum']);
    _perpersonprice = _toDouble(sumdata['perpersonprice']);
    _serviceamt = _toDouble(sumdata['serviceamt']);
    _lowamt = _toDouble(sumdata['lowamt']);
    _amt = _toDouble(sumdata['amt']);
    _zfamt = _toDouble(sumdata['zfamt']);
    _zfcnt = _toDouble(sumdata['zfcnt']);
    _returncnt = _toDouble(sumdata['returncnt']);
    _returnamt = _toDouble(sumdata['returnamt']);

    // 支付方式列表
    if (data['list'] is List) {
      _payList = (data['list'] as List)
          .where((e) => e is Map)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
  }

  /// 提交交班（对齐 smdcapp addShifthandover）
  Future<void> _submitHandover() async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      title: '提示',
      content: '请确认是否现在交班？',
    );
    if (!confirmed || !mounted) return;

    try {
      final String logouttime = _nowStr();
      // 构建 master（对齐 smdcapp HandMasterBean）
      final Map<String, dynamic> master = <String, dynamic>{
        'salecnt': _salecnt.toInt(),
        'returncnt': _returncnt.toInt(),
        'returnamt': _returnamt,
        'saleamt': _saleamt,
        'payableamt': _payableamt,
        'payamt': _payableamt,
        'logintime': _loginTime,
        'logouttime': logouttime,
        'personnum': _personnum,
        'serviceamt': _serviceamt,
        'lowamt': _lowamt,
        'amt': _amt,
        'perpersonprice': _perpersonprice,
      };

      await requestForm(
        HttpApi.addShifthandover,
        <String, dynamic>{
          'master': json.encode(master),
          'details': json.encode(_rawData?['list'] ?? []),
          'printtype': '-1',
          'totalprotype': '-1',
          'totalpro': '-1',
          'totalproret': '-1',
          'totalpropre': '-1',
        },
      );
      Toast.show('交班成功！');
      if (mounted) {
        NavigatorUtils.goBack(context);
      }
    } catch (_) {
      Toast.show('交班失败');
    }
  }

  // ==================== UI ====================

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
          '交接班',
          style: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : Column(
              children: <Widget>[
                Expanded(child: _buildContent()),
                _buildSubmitButton(),
              ],
            ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        // 时间信息
        _buildCard([
          _buildInfoRow('当班人', _getUserName()),
          _buildInfoRow('上班日期', _loginTime),
          _buildInfoRow('交班日期', _logoutTime),
        ]),
        const SizedBox(height: 12),
        // 收入汇总
        _buildCard([
          _buildAmountRow('收入金额', _saleamt, isBold: true),
          _buildAmountRow('应交金额', _payableamt, isBold: true),
          const Divider(height: 16),
          _buildInfoRow('总单数', '${_salecnt.toInt()}'),
          _buildInfoRow('总人数', '${_personnum.toInt()}'),
          _buildAmountRow('人均消费', _perpersonprice),
          _buildAmountRow('消费总额', _amt),
          _buildAmountRow('服务费', _serviceamt),
          _buildAmountRow('低消差额', _lowamt),
        ]),
        const SizedBox(height: 12),
        // 支付统计
        _buildCard([
          const Text('支付统计', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildAmountRow('支付金额', _zfamt),
          _buildInfoRow('支付笔数', '${_zfcnt.toInt()}'),
          _buildInfoRow('退款笔数', '${_returncnt.toInt()}'),
          _buildAmountRow('退款金额', _returnamt),
        ]),
        // 支付方式明细
        if (_payList.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildCard([
            const Text('支付方式明细', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._payList.map((e) => _buildInfoRow(
                  e['payname']?.toString() ?? '未知',
                  '¥${_toDouble(e['rramt']).toStringAsFixed(2)} (${_toDouble(e['billnum']).toInt()}笔)',
                )),
          ]),
        ],
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF666666))),
          Text(value, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))),
        ],
      ),
    );
  }

  Widget _buildAmountRow(String label, double value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: TextStyle(
            fontSize: isBold ? 16 : 14,
            color: const Color(0xFF666666),
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          )),
          Text('¥${value.toStringAsFixed(2)}', style: TextStyle(
            fontSize: isBold ? 18 : 14,
            color: isBold ? const Color(0xFFE13426) : const Color(0xFF333333),
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          )),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: _submitHandover,
          child: Container(
            width: double.infinity,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE13426),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '交班',
              style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 工具方法 ====================

  String _getUserId() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            json.decode(userStr) as Map<String, dynamic>;
        return userMap['userid']?.toString() ?? '0';
      }
    } catch (_) {}
    return '0';
  }

  String _getUserName() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            json.decode(userStr) as Map<String, dynamic>;
        final String name = userMap['name']?.toString() ?? '';
        final String code = userMap['code']?.toString() ?? '';
        return code.isNotEmpty ? '$name($code)' : name;
      }
    } catch (_) {}
    return '';
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _nowStr() {
    final now = DateTime.now();
    return '${_today()} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
