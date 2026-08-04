import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/my_app_bar.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 预订管理页（对齐 smdcapp 预订模块 YDApi）
///
/// 展示预订列表，支持新增预订、取消预订、预订开台、逾期退款。
class ReservePage extends StatefulWidget {
  const ReservePage({super.key});

  @override
  State<ReservePage> createState() => _ReservePageState();
}

class _ReservePageState extends State<ReservePage> {
  List<Map<String, dynamic>> _reserves = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReserves();
  }

  /// 加载预订列表（对齐 smdcapp reserve/findList）
  Future<void> _loadReserves() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.reserveFindList,
        <String, dynamic>{
          'is_page': '0',
          'status': '',
          'cond': '',
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          _reserves = list.whereType<Map<String, dynamic>>().toList();
        }
      } else if (data is List) {
        _reserves = data.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {
      _reserves = <Map<String, dynamic>>[];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 取消预订（对齐 smdcapp reserve/cancel）
  Future<void> _cancelReserve(Map<String, dynamic> reserve) async {
    final bool confirmed = await ConfirmDialog.show(context, content: '确定要取消该预订吗？');
    if (!confirmed || !mounted) return;
    try {
      await requestForm(HttpApi.reserveCancel, <String, dynamic>{
        'billid': reserve['billid']?.toString() ?? reserve['id']?.toString() ?? '',
      });
      if (!mounted) return;
      Toast.show('已取消预订');
      _loadReserves();
    } catch (_) {
      if (mounted) Toast.show('取消失败');
    }
  }

  /// 预订开台（对齐 smdcapp reserve/opentable）
  Future<void> _openTable(Map<String, dynamic> reserve) async {
    final bool confirmed = await ConfirmDialog.show(context, content: '确定为该预订开台吗？');
    if (!confirmed || !mounted) return;
    try {
      await requestForm(HttpApi.reserveOpenTable, <String, dynamic>{
        'billid': reserve['billid']?.toString() ?? reserve['id']?.toString() ?? '',
      });
      if (!mounted) return;
      Toast.show('预订开台成功');
      TableEventBus.fireTableChanged();
      _loadReserves();
    } catch (_) {
      if (mounted) Toast.show('开台失败');
    }
  }

  /// 新增预订（对齐 smdcapp reserve/save）
  Future<void> _addReserve() async {
    final Map<String, dynamic>? result = await _showReserveDialog();
    if (result == null || !mounted) return;
    try {
      await requestForm(HttpApi.reserveSave, <String, dynamic>{
        'data': jsonEncode(result),
      });
      if (!mounted) return;
      Toast.show('预订成功');
      _loadReserves();
    } catch (_) {
      if (mounted) Toast.show('预订失败');
    }
  }

  /// 新增预订弹窗（ConfirmDialog 同风格卡片）
  Future<Map<String, dynamic>?> _showReserveDialog() {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController phoneCtrl = TextEditingController();
    final TextEditingController numCtrl = TextEditingController(text: '4');
    final TextEditingController timeCtrl = TextEditingController();
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext ctx) {
        final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // 标题
                    Text(
                      '新增预订',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1D2129),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _reserveField(nameCtrl, '预订人姓名', isDark),
                    const SizedBox(height: 10),
                    _reserveField(phoneCtrl, '联系电话', isDark, keyboard: TextInputType.phone),
                    const SizedBox(height: 10),
                    _reserveField(numCtrl, '人数', isDark, keyboard: TextInputType.number),
                    const SizedBox(height: 10),
                    _reserveField(timeCtrl, '预订时间(如 2026-07-28 18:00)', isDark),
                    const SizedBox(height: 24),
                    // 按钮区域
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(ctx),
                            child: Container(
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F3F5),
                                borderRadius: BorderRadius.circular(8),
                                border: isDark
                                    ? Border.all(color: const Color(0xFF4A4A4C), width: 0.5)
                                    : null,
                              ),
                              child: Text(
                                '取消',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF4E5969),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) {
                                Toast.show('请填写姓名和电话');
                                return;
                              }
                              Navigator.pop(ctx, <String, dynamic>{
                                'linkman': nameCtrl.text.trim(),
                                'linkphone': phoneCtrl.text.trim(),
                                'personnum': numCtrl.text.trim(),
                                'reservetime': timeCtrl.text.trim(),
                                'status': '0',
                              });
                            },
                            child: Container(
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _kBrandRed,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: _kBrandRed.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Text(
                                '确定',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 预订弹窗输入框（与 InputDialog 输入框同风格）
  Widget _reserveField(
    TextEditingController ctrl,
    String hint,
    bool isDark, {
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: TextStyle(
        fontSize: 14,
        color: isDark ? Colors.white : const Color(0xFF1D2129),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
        filled: true,
        fillColor: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF7F8FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E6EB), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBrandRed, width: 1.2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: const MyAppBar(centerTitle: '预订管理'),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kBrandRed,
        onPressed: _addReserve,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reserves.isEmpty
              ? const Center(child: Text('暂无预订记录', style: TextStyle(color: Color(0xFF999999))))
              : RefreshIndicator(
                  onRefresh: _loadReserves,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _reserves.length,
                    itemBuilder: (BuildContext ctx, int i) => _buildReserveCard(_reserves[i]),
                  ),
                ),
    );
  }

  Widget _buildReserveCard(Map<String, dynamic> reserve) {
    final String name = reserve['linkman']?.toString() ?? reserve['name']?.toString() ?? '';
    final String phone = reserve['linkphone']?.toString() ?? reserve['phone']?.toString() ?? '';
    final String personnum = reserve['personnum']?.toString() ?? '';
    final String reservetime = reserve['reservetime']?.toString() ?? '';
    final int status = int.tryParse(reserve['status']?.toString() ?? '0') ?? 0;

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
                child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: status == 0 ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status == 0 ? '待到店' : '已完成',
                  style: TextStyle(fontSize: 11, color: status == 0 ? Colors.orange : Colors.green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('电话：$phone', style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
          const SizedBox(height: 4),
          Text('人数：$personnum  时间：$reservetime', style: const TextStyle(fontSize: 12, color: Color(0xFF999999))),
          if (status == 0) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => _cancelReserve(reserve),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('取消预订'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _openTable(reserve),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrandRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('预订开台'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
