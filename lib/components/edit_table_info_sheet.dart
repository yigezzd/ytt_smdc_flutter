import 'package:flutter/material.dart';
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
/// 支持修改人数、备注。确认后调用 updateMasterTmp 接口。
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
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _personCtrl = TextEditingController(text: widget.personnum);
    _remarkCtrl = TextEditingController(text: widget.remark);
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
                    child: Text('修改开台信息 - ${widget.tableName}',
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
                controller: _personCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '人数',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remarkCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(),
                ),
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
                      : const Text('保存', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 提交修改（对齐 smdcapp updateMasterTmp）
  Future<void> _submit() async {
    final String personnum = _personCtrl.text.trim();
    if (personnum.isEmpty) {
      Toast.show('请输入人数');
      return;
    }
    setState(() => _submitting = true);
    try {
      await OrderRepository.updateMasterTmpVip(
        saleid: widget.saleid,
        tableid: widget.tableId,
        tablecode: widget.tableCode,
        remark: _remarkCtrl.text.trim(),
        personnum: personnum,
        serverid: widget.serverId,
        servername: widget.serverName,
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
