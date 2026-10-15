import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/db/deposit_dao.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/pay_gateway.dart';
import 'package:flutter_deer/pages/order/pay_scan_page.dart';
import 'package:flutter_deer/pages/order/scan_pay_dialog.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/print_service.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:intl/intl.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 打印押金单开关存储 key（对齐 smdcapp MMKV Constant.DY_YJ）
const String _kDepositPrintFlagKey = 'deposit_print_flag';

/// 押金弹窗（对齐 smdcapp JYJPopup - 交押金）
///
/// 金额输入 + 支付方式选择（depositflag=1 的方式）+ 打印押金单开关
/// → 调用 deposit/save 接口（printtype=13 时服务端出押金单）
class DepositSheet extends StatefulWidget {
  const DepositSheet({
    super.key,
    required this.saleid,
    required this.tableId,
    required this.tableName,
    this.serverId = '',
    this.serverName = '',
  });

  final String saleid;
  final String tableId;
  final String tableName;
  final String serverId;
  final String serverName;

  /// 显示交押金弹窗
  static Future<bool> showPay(
    BuildContext context, {
    required String saleid,
    required String tableId,
    required String tableName,
    String serverId = '',
    String serverName = '',
  }) async {
    final bool? result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DepositSheet(
        saleid: saleid,
        tableId: tableId,
        tableName: tableName,
        serverId: serverId,
        serverName: serverName,
      ),
    );
    return result ?? false;
  }

  /// 显示押金记录弹窗（对齐 smdcapp YJOrderActivity）
  static Future<void> showRecords(
    BuildContext context, {
    required String saleid,
    String tableId = '',
    String tableName = '',
    String serverId = '',
    String serverName = '',
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DepositRecordSheet(
        saleid: saleid,
        tableId: tableId,
        tableName: tableName,
        serverId: serverId,
        serverName: serverName,
      ),
    );
  }

  @override
  State<DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends State<DepositSheet> {
  final TextEditingController _amtCtrl = TextEditingController();
  bool _submitting = false;

  /// 有效押金支付方式（对齐 smdcapp JYJPopup.setPayData 过滤规则）
  List<Map<String, dynamic>> _payWays = <Map<String, dynamic>>[];
  Map<String, dynamic>? _selectedPay;

  /// 打印押金单开关（对齐 smdcapp isDy，持久化记忆）
  bool _printBill = false;

  @override
  void initState() {
    super.initState();
    _printBill = SpUtil.getBool(_kDepositPrintFlagKey) ?? false;
    _loadPayWays();
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  /// 获取可交押金的支付方式（对齐 smdcapp：operflag!=0 且 depositflag==1，
  /// 排除 抖音/会员卡02/挂账12）
  Future<void> _loadPayWays() async {
    List<Map<String, dynamic>> ways = <Map<String, dynamic>>[];
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.getPayInfoList,
        <String, dynamic>{
          'cond': '',
          'stopflag': '0',
          'pagesize': '100',
          'field': 'isort',
          'type': 'asc',
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic> && data['list'] is List) {
        ways = (data['list'] as List).whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    ways = ways.where((Map<String, dynamic> w) {
      final String payid = w['payid']?.toString() ?? '';
      if (payid.isEmpty || payid == 'douyin' || payid == '02' || payid == '12') {
        return false;
      }
      if ((w['depositflag']?.toString() ?? '') != '1') return false;
      if ((w['operflag']?.toString() ?? '1') == '0') return false;
      return true;
    }).toList();
    if (!mounted) return;
    setState(() {
      _payWays = ways;
      _selectedPay = ways.isNotEmpty
          ? (ways.firstWhere(
              (Map<String, dynamic> w) => w['payid']?.toString() == '01',
              orElse: () => ways[0],
            ))
          : <String, dynamic>{'payid': '01', 'name': '现金'}; // 兜底现金
    });
  }

  @override
  Widget build(BuildContext context) {
    final String payName = _selectedPay?['name']?.toString() ?? '现金';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFE5E6EB), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('交押金 - ${widget.tableName}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFFC9CDD4)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('押金金额',
                  style: TextStyle(fontSize: 13, color: Color(0xFF86909C))),
              const SizedBox(height: 8),
              // 金额输入（样式对齐 InputDialog：浅灰底 + 圆角 + 聚焦品牌红描边）
              TextField(
                controller: _amtCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1D2129)),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '0.00',
                  hintStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.normal, color: Color(0xFFC9CDD4)),
                  prefixText: '¥ ',
                  prefixStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1D2129)),
                  filled: true,
                  fillColor: const Color(0xFFF7F8FA),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE5E6EB), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _kBrandRed, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 支付方式（对齐 smdcapp JYJPopup ll_pay_type：点击弹出可选支付方式）
              InkWell(
                onTap: _showPayWayPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE5E6EB)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Text('支付方式', style: TextStyle(fontSize: 14, color: Color(0xFF4E5969))),
                      const Spacer(),
                      Text(payName,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1D2129))),
                      const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC9CDD4)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 打印押金单开关（对齐 smdcapp img_yj：printtype=13）
              Row(
                children: <Widget>[
                  const Spacer(),
                  const Text('打印押金单', style: TextStyle(fontSize: 14, color: Color(0xFF4E5969))),
                  const SizedBox(width: 6),
                  Switch(
                    value: _printBill,
                    activeTrackColor: _kBrandRed,
                    onChanged: (bool v) {
                      setState(() => _printBill = v);
                      SpUtil.putBool(_kDepositPrintFlagKey, v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrandRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Text('确认交押金', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 支付方式选择弹窗（对齐 smdcapp PayTypeDialog 选择回显）
  Future<void> _showPayWayPicker() async {
    if (_payWays.length <= 1) return;
    final Map<String, dynamic>? picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 10),
                Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E6EB), borderRadius: BorderRadius.circular(2))),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('选择支付方式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _payWays.length,
                    itemBuilder: (BuildContext c, int i) {
                      final Map<String, dynamic> w = _payWays[i];
                      final bool selected =
                          w['payid']?.toString() == _selectedPay?['payid']?.toString();
                      return ListTile(
                        title: Text(w['name']?.toString() ?? '',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                color: selected ? _kBrandRed : const Color(0xFF1D2129))),
                        trailing: selected
                            ? const Icon(Icons.check, size: 18, color: _kBrandRed)
                            : null,
                        onTap: () => Navigator.pop(ctx, w),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedPay = picked);
    }
  }

  /// 提交押金（对齐 smdcapp JYJPopup.savePayData → /YttSvr/deposit/save）
  Future<void> _submit() async {
    final double amt = double.tryParse(_amtCtrl.text.trim()) ?? 0;
    if (amt <= 0) {
      Toast.show('请输入有效金额');
      return;
    }
    final Map<String, dynamic> pay = _selectedPay ?? <String, dynamic>{'payid': '01', 'name': '现金'};
    final String payid = pay['payid']?.toString() ?? '01';
    final String payname = pay['name']?.toString() ?? '现金';

    setState(() => _submitting = true);
    try {
      // 已交押金校验（对齐 smdcapp JYJPopup.selectPay：已交押金需先退还）
      final List<Map<String, dynamic>> active = await _fetchActiveDeposits();
      if (active.isNotEmpty) {
        final Map<String, dynamic> first = active.first;
        if (mounted) {
          Toast.show(
              '桌台[${widget.tableName}]已交押金[${first['payname'] ?? ''} ${first['payamt'] ?? 0}]元，请退还押金，再重新交押金');
        }
        return;
      }

      // 扫码类支付方式：先扫码收款（对齐 smdcapp：08/09/10 走扫码支付）
      String tradeNo = '';
      String thirdOrderNo = '';
      if (_isScanPay(pay)) {
        final ScanPayResult? result = await _scanPay(amt, payid);
        if (result == null || !result.success) {
          if (result != null && mounted) {
            Toast.show(result.errorMsg.isNotEmpty ? result.errorMsg : '支付失败');
          }
          return;
        }
        final List<String> parts = result.trade.split(',');
        tradeNo = parts.isNotEmpty ? parts[0] : result.trade;
        thirdOrderNo = parts.length > 1 ? parts[1] : '';
      }

      // 对齐 smdcapp: operid/opername 优先取桌台服务员，否则取当前登录用户
      String operid = widget.serverId;
      String opername = widget.serverName;
      try {
        final String userStr = SpUtil.getString(Constant.user) ?? '';
        if (userStr.isNotEmpty) {
          final Map<String, dynamic> userMap =
              jsonDecode(userStr) as Map<String, dynamic>;
          if (operid.isEmpty) {
            operid = userMap['userid']?.toString() ?? '';
          }
          if (opername.isEmpty) {
            opername = userMap['username']?.toString() ?? '';
          }
        }
      } catch (_) {}

      // 对齐 smdcapp: sid/spid 取自登录存储的门店信息
      String sid = '0';
      String spid = '0';
      try {
        final String storeStr = SpUtil.getString(Constant.store) ?? '';
        if (storeStr.isNotEmpty) {
          final Map<String, dynamic> storeMap =
              jsonDecode(storeStr) as Map<String, dynamic>;
          sid = storeMap['id']?.toString() ?? '0';
          spid = storeMap['spid']?.toString() ?? '0';
        }
      } catch (_) {}

      final String machNo = SpUtil.getString(Constant.machNo) ?? '';
      final String usetime =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

      // 对齐 smdcapp BillUtils.getYjBillon(): "YJ" + yyMMdd + machNo + random7
      final DateTime now = DateTime.now();
      final String yyMMdd = '${(now.year % 100).toString().padLeft(2, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final String billno = 'YJ$yyMMdd$machNo${_randomString(7)}';

      // 对齐 smdcapp DepositBeanDate 全字段
      final Map<String, dynamic> depositData = <String, dynamic>{
        'onlyid': '',
        'tableid': widget.tableId,
        'tablename': widget.tableName,
        'saleid': widget.saleid,
        'status': '1',
        'payamt': amt.toString(),
        'rate': '1.0',
        'rramt': amt.toString(),
        'payname': payname,
        'payid': payid,
        'refundamt': '0.0',
        'third_order_no': thirdOrderNo,
        'trade_no': tradeNo,
        'refund_third_no': '',
        'refund_trade_no': '',
        'operid': operid,
        'opername': opername,
        'machno': machNo,
        'usetime': usetime,
        'sid': sid,
        'spid': spid,
        'billno': billno,
      };
      await requestForm(HttpApi.depositSave, <String, dynamic>{
        'data': jsonEncode(depositData),
        // 打印押金单（对齐 smdcapp isDy → printtype=13）
        'printtype': _printBill ? '13' : '-1',
      });
      // 双写本地押金流水（非 Web；失败静默，不阻断流程）
      if (!kIsWeb) {
        try {
          await DepositDao.instance.saveDeposit(depositData);
        } catch (e) {
          debugPrint('本地押金流水写入失败: $e');
        }
      }
      // 打印押金单（对齐 smdcapp：PC 模式调 /api/print/PrintDepositInfo）
      if (_printBill) {
        try {
          await PrintService.instance.printDeposit(jsonEncode(depositData));
        } catch (_) {}
      }
      if (!mounted) return;
      Toast.show('交押金成功');
      Navigator.pop(context, true);
    } catch (e) {
      // 透出服务端返回的失败原因，便于定位（此前统一显示"交押金失败"无法排查）
      if (mounted) {
        Toast.show('交押金失败：${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 查询桌台上仍在使用的押金（对齐 smdcapp JYJPopup.getOrderDetailList：
  /// deposit/findList + status=1，由服务端过滤在用押金）
  Future<List<Map<String, dynamic>>> _fetchActiveDeposits() async {
    final List<Map<String, dynamic>> active = <Map<String, dynamic>>[];
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.depositFindList,
        <String, dynamic>{
          'is_page': '0',
          'cond': '',
          'status': '1',
          'starttime': '',
          'endtime': '',
          'type': '1',
          'saleid': widget.saleid,
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic> && data['list'] is List) {
        active.addAll((data['list'] as List).whereType<Map<String, dynamic>>());
      }
    } catch (_) {}
    return active;
  }

  /// 是否扫码支付方式（对齐 smdcapp JYJPopup.selectPay 与结账页 settle_page：
  /// 仅 支付宝08/微信09/云闪付10 走扫码，现金01 及自定义支付直接收款。
  /// 注意：payway 的 scanflag 是「扫码点餐」标志，与扫码收款无关，勿用于此判断）
  bool _isScanPay(Map<String, dynamic> pay) {
    final String payid = pay['payid']?.toString() ?? '';
    return payid == '08' || payid == '09' || payid == '10';
  }

  /// 扫码收款（复用结账扫码支付组件，对齐 smdcapp disposeWxAliScanPay）
  Future<ScanPayResult?> _scanPay(double amt, String payid) async {
    final Object? scanResult = await Navigator.push<Object>(
      context,
      MaterialPageRoute<Object>(builder: (_) => const PayScanPage()),
    );
    if (scanResult == null || scanResult.toString().isEmpty || !mounted) {
      return null;
    }
    final String authCode = scanResult.toString();
    final Map<String, String> cfg = _storePayConfig();
    if (cfg['terminalsn']!.isEmpty || cfg['terminalkey']!.isEmpty) {
      Toast.show('支付配置不完整，请使用其他支付方式');
      return null;
    }
    final PayGateway gateway = PayGateway(
      terminalsn: cfg['terminalsn']!,
      terminalkey: cfg['terminalkey']!,
      payType: cfg['paytype']!,
      shopId: cfg['shopid']!,
      operator: _operatorName(),
    );
    final String payBillNo = _generateBillNo() + _paySuffix();
    return ScanPayDialog.show(
      context,
      payid: payid,
      amt: amt,
      billNo: payBillNo,
      authCode: authCode,
      gateway: gateway,
    );
  }

  /// 门店支付配置（对齐 smdcapp MMKV: terminalsn/terminalkey/payType/shopid）
  Map<String, String> _storePayConfig() {
    Map<String, dynamic> storeMap = <String, dynamic>{};
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
      }
    } catch (_) {}
    if ((storeMap['terminalsn']?.toString() ?? '').isEmpty) {
      try {
        final String allDataStr = SpUtil.getString(Constant.allLoginData) ?? '';
        if (allDataStr.isNotEmpty) {
          final Map<String, dynamic> allData =
              jsonDecode(allDataStr) as Map<String, dynamic>;
          final dynamic storeRaw = allData['store'];
          if (storeRaw is Map) {
            Map<String, dynamic>.from(storeRaw).forEach((String key, dynamic value) {
              storeMap.putIfAbsent(key, () => value);
            });
          }
        }
      } catch (_) {}
    }
    return <String, String>{
      'paytype': storeMap['paytype']?.toString() ?? '4',
      'terminalsn': storeMap['terminalsn']?.toString() ?? '',
      'terminalkey': storeMap['terminalkey']?.toString() ?? '',
      'shopid': storeMap['shopid']?.toString() ?? '',
    };
  }

  String _operatorName() {
    try {
      final String userStr = SpUtil.getString(Constant.user) ?? '';
      if (userStr.isNotEmpty) {
        final Map<String, dynamic> userMap =
            jsonDecode(userStr) as Map<String, dynamic>;
        return userMap['username']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  /// 支付订单号（对齐 smdcapp OrderModel.getBillno 格式）
  String _generateBillNo() {
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  /// 支付订单号后缀（对齐 smdcapp geSuffixNum: "A" + HHmmss）
  String _paySuffix() {
    final DateTime now = DateTime.now();
    return 'A${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }

  /// 随机字符串（对齐 smdcapp BillUtils.getRandomString）
  static String _randomString(int length) {
    const String chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final Random random = Random();
    return String.fromCharCodes(Iterable<int>.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(62))));
  }
}

/// 押金记录弹窗（对齐 smdcapp YJOrderActivity：记录 + 补打 + 原路退回）
class _DepositRecordSheet extends StatefulWidget {
  const _DepositRecordSheet({
    required this.saleid,
    this.tableId = '',
    this.tableName = '',
    this.serverId = '',
    this.serverName = '',
  });
  final String saleid;
  final String tableId;
  final String tableName;
  final String serverId;
  final String serverName;

  @override
  State<_DepositRecordSheet> createState() => _DepositRecordSheetState();
}

class _DepositRecordSheetState extends State<_DepositRecordSheet> {
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _refunding = false;

  /// 押金状态文案（对齐 smdcapp：1未使用 2已使用 3已退回 4部分退回）
  static const Map<String, String> _statusText = <String, String>{
    '1': '未使用',
    '2': '已使用',
    '3': '已退回',
    '4': '部分退回',
  };

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  /// 加载押金记录（对齐 smdcapp YJOrderActivity.getOrderDetailList：
  /// deposit/findList，返回 DepositListBean 全字段：payname/opername/billno/status 等）
  Future<void> _loadRecords() async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.depositFindList,
        <String, dynamic>{
          'is_page': '0',
          'cond': '',
          'status': '',
          'starttime': '',
          'endtime': '',
          'type': '1',
          'saleid': widget.saleid,
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          _records = list.whereType<Map<String, dynamic>>().toList();
        }
      } else if (data is List) {
        _records = data.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Center(
            child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E6EB), borderRadius: BorderRadius.circular(2))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.tableName.isNotEmpty ? '押金记录-${widget.tableName}' : '押金记录',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20, color: Color(0xFFC9CDD4))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ColoredBox(
                    color: const Color(0xFFF9F9F9),
                    child: _records.isEmpty
                        ? const Center(
                            child: Text('暂无押金记录',
                                style: TextStyle(color: Color(0xFF999999))))
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 10),
                            itemCount: _records.length,
                            itemBuilder: (BuildContext ctx, int i) =>
                                _buildRecord(_records[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 单条押金记录卡片（对齐 smdcapp yj_order_item.xml + YJOrderActivity.onBind）
  Widget _buildRecord(Map<String, dynamic> r) {
    final int status = _toInt(r['status']);
    final double payamt = _toDouble(r['payamt']);
    final double refundamt = _toDouble(r['refundamt']);
    // 可使用金额：押金金额>0 取 押金-退款，否则取押金（对齐 YJOrderActivity.onBind）
    final double usable = payamt > 0 ? _sub2(payamt, refundamt) : payamt;
    // 原路退回：状态为 2已使用/3已退回/4部分退回 时隐藏（对齐 btAllRefund 可见性规则）
    final bool canRefund = status != 2 && status != 3 && status != 4;
    final String opername = r['opername']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(16, 10, 18, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _recordText('押金金额：${_amt(payamt)}')),
              Expanded(child: _recordText('付款方式：${r['payname'] ?? ''}')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: _recordText('退款金额：${_amt(refundamt)}')),
              Expanded(
                  child: _recordText(opername.isNotEmpty ? '操作员：$opername' : '')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _recordText('可使用金额：'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text('￥${_amt(usable)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _kBrandRed)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _recordText('单号：${r['billno'] ?? ''}'),
          const SizedBox(height: 8),
          _recordText('时间：${_firstNonEmpty(r['createtime'], r['usetime'])}'),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _statusText[status.toString()] ?? '',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0092E0)),
                ),
              ),
              // 补打（对齐 smdcapp btPrint：PC 模式 PrintDepositInfo）
              SizedBox(
                width: 70,
                height: 35,
                child: OutlinedButton(
                  onPressed: _refunding ? null : () => _reprint(r),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _kBrandRed,
                    side: const BorderSide(color: _kBrandRed),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text('补打', style: TextStyle(fontSize: 13)),
                ),
              ),
              // 原路退回（对齐 smdcapp btAllRefund：仅未使用/未退回的押金可退）
              if (canRefund) ...<Widget>[
                const SizedBox(width: 10),
                SizedBox(
                  width: 70,
                  height: 35,
                  child: ElevatedButton(
                    onPressed: _refunding ? null : () => _refund(r),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBrandRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: const Text('原路退回', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _recordText(String text) => Text(
        text,
        style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  String _firstNonEmpty(dynamic a, dynamic b) {
    final String s1 = a?.toString() ?? '';
    if (s1.isNotEmpty) return s1;
    return b?.toString() ?? '';
  }

  /// 补打押金单（对齐 smdcapp YJOrderActivity btPrint → PcSendPrint/PrintDepositInfo）
  Future<void> _reprint(Map<String, dynamic> r) async {
    try {
      final bool ok = await PrintService.instance.printDeposit(jsonEncode(r));
      if (!mounted) return;
      Toast.show(ok ? '补打成功' : '补打失败，请检查打印机配置');
    } catch (e) {
      if (mounted) Toast.show('补打失败：$e');
    }
  }

  /// 原路退回（对齐 smdcapp YjRefundModel.dealPayWay + savePayData）：
  /// - 未使用押金：全额退回 rramt，status=3 已退回
  /// - 部分使用：退回差额 rramt-userpayamt，status=4 部分退回
  /// - 已用完：不退金额，status=2 已使用
  /// 扫码支付（08/09/10）先走支付网关退款，现金等线下方式直接更新流水
  Future<void> _refund(Map<String, dynamic> r) async {
    if (_refunding) return;
    final double rramt = _toDouble(r['rramt']);
    final double userpayamt = _toDouble(r['userpayamt']);
    final double backAmt = _sub2(rramt, userpayamt);
    // 部分退回：smdcapp 扫码分支传 2 与注释及线下分支(4)不一致，此处按 4 处理
    final String newStatus = userpayamt > 0 ? (backAmt > 0 ? '4' : '2') : '3';
    final double refundamt =
        newStatus == '3' ? rramt : (newStatus == '4' ? backAmt : 0);

    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '确定退回该笔押金 ¥${_amt(backAmt)} 吗？',
    );
    if (!confirmed || !mounted) return;

    final String payid = r['payid']?.toString() ?? '';
    final bool isScan = payid == '08' || payid == '09' || payid == '10';
    String refundTrade = '';
    setState(() => _refunding = true);
    try {
      if (isScan && backAmt > 0) {
        // 扫码支付：先原路退款（对齐 smdcapp RefundUtil_les/RefundUtil_BY/RefundUtil）
        final Map<String, String> cfg = _storePayConfigForRefund();
        if (cfg['terminalsn']!.isEmpty || cfg['terminalkey']!.isEmpty) {
          Toast.show('支付配置不完整，无法原路退回');
          return;
        }
        final PayGateway gateway = PayGateway(
          terminalsn: cfg['terminalsn']!,
          terminalkey: cfg['terminalkey']!,
          payType: cfg['paytype']!,
          shopId: cfg['shopid']!,
        );
        final int fen = (backAmt * 100).round();
        final bool refundOk = await gateway.refund(
          billNo: _firstNonEmpty(r['third_order_no'], r['billno']),
          refundNo: 'YJ${DateTime.now().millisecondsSinceEpoch}',
          totalAmtFen: fen,
          refundAmtFen: fen,
          tradeNo: r['trade_no']?.toString() ?? '',
        );
        if (!refundOk) {
          Toast.show('原路退回失败，请前往收银机处理');
          return;
        }
        refundTrade = r['trade_no']?.toString() ?? '';
      }

      // 更新押金流水状态（对齐 smdcapp savePayData：操作员优先取桌台服务员，
      // 否则取当前登录用户）
      String operid = widget.serverId;
      String opername = widget.serverName;
      try {
        final String userStr = SpUtil.getString(Constant.user) ?? '';
        if (userStr.isNotEmpty) {
          final Map<String, dynamic> userMap =
              jsonDecode(userStr) as Map<String, dynamic>;
          if (operid.isEmpty) operid = userMap['userid']?.toString() ?? '';
          if (opername.isEmpty) opername = userMap['username']?.toString() ?? '';
        }
      } catch (_) {}

      final Map<String, dynamic> updateData = <String, dynamic>{
        'onlyid': r['onlyid']?.toString() ?? '',
        'tableid': r['tableid']?.toString() ?? widget.tableId,
        'tablename': r['tablename']?.toString() ?? widget.tableName,
        'saleid': r['saleid']?.toString() ?? widget.saleid,
        'status': newStatus,
        'payamt': r['payamt']?.toString() ?? '0',
        'rate': r['rate']?.toString() ?? '1.0',
        'rramt': r['rramt']?.toString() ?? '0',
        'payname': r['payname']?.toString() ?? '',
        'payid': payid,
        'refundamt': _amt(refundamt),
        'third_order_no': r['third_order_no']?.toString() ?? '',
        'trade_no': r['trade_no']?.toString() ?? '',
        'refund_third_no': '',
        'refund_trade_no': refundTrade,
        'operid': operid,
        'opername': opername,
        'machno': r['machno']?.toString() ?? (SpUtil.getString(Constant.machNo) ?? ''),
        'usetime': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
        'sid': r['sid']?.toString() ?? '0',
        'spid': r['spid']?.toString() ?? '0',
      };
      await requestForm(HttpApi.depositUpdate, <String, dynamic>{
        'data': jsonEncode(updateData),
      });
      if (!kIsWeb) {
        try {
          await DepositDao.instance.updateDeposit(updateData);
        } catch (e) {
          debugPrint('本地押金流水更新失败: $e');
        }
      }
      if (!mounted) return;
      Toast.show('操作成功');
      setState(() => _loading = true);
      _loadRecords();
    } catch (e) {
      if (mounted) {
        Toast.show('退回失败：${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _refunding = false);
    }
  }

  /// 门店支付配置（退款用）
  Map<String, String> _storePayConfigForRefund() {
    Map<String, dynamic> storeMap = <String, dynamic>{};
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        storeMap = jsonDecode(storeStr) as Map<String, dynamic>;
      }
    } catch (_) {}
    if ((storeMap['terminalsn']?.toString() ?? '').isEmpty) {
      try {
        final String allDataStr = SpUtil.getString(Constant.allLoginData) ?? '';
        if (allDataStr.isNotEmpty) {
          final Map<String, dynamic> allData =
              jsonDecode(allDataStr) as Map<String, dynamic>;
          final dynamic storeRaw = allData['store'];
          if (storeRaw is Map) {
            Map<String, dynamic>.from(storeRaw).forEach((String key, dynamic value) {
              storeMap.putIfAbsent(key, () => value);
            });
          }
        }
      } catch (_) {}
    }
    return <String, String>{
      'paytype': storeMap['paytype']?.toString() ?? '4',
      'terminalsn': storeMap['terminalsn']?.toString() ?? '',
      'terminalkey': storeMap['terminalkey']?.toString() ?? '',
      'shopid': storeMap['shopid']?.toString() ?? '',
    };
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  /// 金额显示对齐 smdcapp（Kotlin Double.toString：100.0 / 0.0 / 66.67）
  String _amt(double v) => v.toString();

  /// 对齐 smdcapp CalcUtils.sub2（保留 2 位，四舍五入）
  double _sub2(double a, double b) =>
      ((a * 100).round() - (b * 100).round()) / 100;
}
