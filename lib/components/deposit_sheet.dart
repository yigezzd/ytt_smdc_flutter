import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/db/deposit_dao.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:intl/intl.dart';
import 'package:sp_util/sp_util.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 押金弹窗（对齐 smdcapp JYJPopup - 交押金）
///
/// 输入押金金额 → 调用 deposit/save 接口
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

  /// 显示押金记录弹窗
  static Future<void> showRecords(
    BuildContext context, {
    required String saleid,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DepositRecordSheet(saleid: saleid),
    );
  }

  @override
  State<DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends State<DepositSheet> {
  final TextEditingController _amtCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              TextField(
                controller: _amtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '押金金额',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 20),
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

  /// 提交押金（对齐 smdcapp JYJPopup.savePayData → /YttSvr/deposit/save）
  Future<void> _submit() async {
    final double amt = double.tryParse(_amtCtrl.text.trim()) ?? 0;
    if (amt <= 0) {
      Toast.show('请输入有效金额');
      return;
    }
    setState(() => _submitting = true);
    try {
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

      // 对齐 smdcapp DepositBeanDate 全字段（默认现金支付 payid=01）
      final Map<String, dynamic> depositData = <String, dynamic>{
        'onlyid': '',
        'tableid': widget.tableId,
        'tablename': widget.tableName,
        'saleid': widget.saleid,
        'status': '1',
        'payamt': amt.toString(),
        'rate': '1.0',
        'rramt': amt.toString(),
        'payname': '现金',
        'payid': '01',
        'refundamt': '0.0',
        'third_order_no': '',
        'trade_no': '',
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
        'printtype': '-1',
      });
      // 双写本地押金流水（非 Web；失败静默，不阻断流程）
      if (!kIsWeb) {
        try {
          await DepositDao.instance.saveDeposit(depositData);
        } catch (e) {
          debugPrint('本地押金流水写入失败: $e');
        }
      }
      if (!mounted) return;
      Toast.show('交押金成功');
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) Toast.show('交押金失败');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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

/// 押金记录弹窗（对齐 smdcapp YJOrderActivity）
class _DepositRecordSheet extends StatefulWidget {
  const _DepositRecordSheet({required this.saleid});
  final String saleid;

  @override
  State<_DepositRecordSheet> createState() => _DepositRecordSheetState();
}

class _DepositRecordSheetState extends State<_DepositRecordSheet> {
  List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.depositFindListBySaleid,
        <String, dynamic>{'saleids': widget.saleid},
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
      height: MediaQuery.of(context).size.height * 0.6,
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
                const Expanded(child: Text('押金记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20, color: Color(0xFFC9CDD4))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const Center(child: Text('暂无押金记录', style: TextStyle(color: Color(0xFF999999))))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _records.length,
                        itemBuilder: (BuildContext ctx, int i) {
                          final Map<String, dynamic> r = _records[i];
                          return ListTile(
                            dense: true,
                            title: Text('¥${r['payamt'] ?? '0'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${r['createtime'] ?? ''}  ${r['opername'] ?? ''}'),
                            trailing: Text(
                              r['status']?.toString() == '1' ? '已退' : '有效',
                              style: TextStyle(color: r['status']?.toString() == '1' ? Colors.grey : Colors.green),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
