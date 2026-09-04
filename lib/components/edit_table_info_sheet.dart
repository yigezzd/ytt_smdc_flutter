import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/dish_operation_dialogs.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 修改开台信息结果
class EditTableInfoResult {
  const EditTableInfoResult({
    required this.personnum,
    required this.remark,
  });

  final String personnum;
  final String remark;
}

/// 修改开台信息弹窗（对齐 smdcapp TableOpenBottomDialog 修改模式）
///
/// 支持修改人数、服务员、备注。确认后调用 updateMasterTmp 接口。
/// UI 风格与订单页内联修改开台信息弹窗（图一样式）统一。
class EditTableInfoSheet extends StatefulWidget {
  const EditTableInfoSheet({
    super.key,
    required this.saleid,
    required this.tableId,
    required this.tableCode,
    required this.tableName,
    required this.personnum,
    required this.remark,
    required this.serverId,
    required this.serverName,
    this.tableJson,
  });

  final String saleid;
  final String tableId;
  final String tableCode;
  final String tableName;
  final String personnum;
  final String remark;
  final String serverId;
  final String serverName;
  final Map<String, dynamic>? tableJson;

  /// 显示弹窗并执行修改，返回是否成功
  static Future<bool> show(BuildContext context, {
    required String saleid,
    required String tableId,
    required String tableCode,
    required String tableName,
    required String personnum,
    required String remark,
    required String serverId,
    required String serverName,
    Map<String, dynamic>? tableJson,
  }) async {
    final bool? result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditTableInfoSheet(
        saleid: saleid,
        tableId: tableId,
        tableCode: tableCode,
        tableName: tableName,
        personnum: personnum,
        remark: remark,
        serverId: serverId,
        serverName: serverName,
        tableJson: tableJson,
      ),
    );
    return result ?? false;
  }

  @override
  State<EditTableInfoSheet> createState() => _EditTableInfoSheetState();
}

class _EditTableInfoSheetState extends State<EditTableInfoSheet> {
  late TextEditingController _personCtrl;
  late TextEditingController _remarkCtrl;
  late String _serverId;
  late String _serverName;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _personCtrl = TextEditingController(text: widget.personnum);
    _remarkCtrl = TextEditingController(text: widget.remark);
    _serverId = widget.serverId;
    _serverName =
        widget.serverName.isNotEmpty ? widget.serverName : '系统管理员';
  }

  @override
  void dispose() {
    _personCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 标题栏
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '修改开台信息',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1D2129),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 22, color: Color(0xFF86909C)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 人数
          Row(
            children: <Widget>[
              const Text('人数：', style: TextStyle(fontSize: 15, color: Color(0xFF4E5969))),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                height: 40,
                child: TextField(
                  controller: _personCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  textAlign: TextAlign.center,
                  onTap: () {
                    // 聚焦时自动选中全部文本
                    _personCtrl.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _personCtrl.text.length,
                    );
                  },
                  style: const TextStyle(fontSize: 15, color: Color(0xFF1D2129)),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: _kBrandRed),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 服务员
          Row(
            children: <Widget>[
              const Text('服务员：', style: TextStyle(fontSize: 15, color: Color(0xFF4E5969))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final Waiter? waiter = await DishWaiterSheet.show(
                    context,
                    dishName: widget.tableName,
                    currentWaiter: _serverName,
                  );
                  if (waiter != null && mounted) {
                    setState(() {
                      _serverName = waiter.name;
                      _serverId = waiter.userid;
                    });
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _serverName,
                      style: const TextStyle(fontSize: 15, color: Color(0xFF1D2129)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 18, color: Color(0xFF86909C)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 备注
          Row(
            children: <Widget>[
              const Text('备注：', style: TextStyle(fontSize: 15, color: Color(0xFF4E5969))),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _remarkCtrl,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1D2129)),
                    decoration: InputDecoration(
                      hintText: '请输入备注',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFC9CDD4)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Color(0xFFE5E6EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: _kBrandRed),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 按钮行：取消 + 确定
          Row(
            children: <Widget>[
              // 取消
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E6EB)),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Center(
                      child: Text(
                        '取消',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF4E5969)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 确定
              Expanded(
                child: GestureDetector(
                  onTap: _submitting ? null : _submit,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Center(
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '确定',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 提交修改（对齐 smdcapp updateMasterTmp）
  Future<void> _submit() async {
    final int personNum = int.tryParse(_personCtrl.text.trim()) ?? 0;
    if (personNum <= 0) {
      Toast.show('请输入正确的人数！');
      return;
    }
    setState(() => _submitting = true);
    try {
      await OrderRepository.updateMasterTmpVip(
        saleid: widget.saleid,
        tableid: widget.tableId,
        tablecode: widget.tableCode,
        remark: _remarkCtrl.text.trim(),
        personnum: '$personNum',
        serverid: _serverId,
        servername: _serverName,
        vipid: '',
        vipno: '',
        vipname: '',
        vipmobile: '',
        masterDevice: ConnectionManager.pcAlive,
        tableJson: widget.tableJson,
      );
      if (!mounted) return;
      Toast.show('修改成功');
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) Toast.show('修改失败');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
