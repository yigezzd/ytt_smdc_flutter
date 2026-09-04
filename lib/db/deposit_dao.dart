import 'package:intl/intl.dart';

import 'app_database.dart';

/// 押金流水写入 DAO（对齐 YttPhone DepositFlowDao + smdcapp JYJPopup.savePayData）
///
/// deposit/save 云端成功后双写本地 t_deposit_flow；
/// [data] 为 deposit_sheet 构建的 depositData（字段与 DepositBeanDate 一致），
/// 缺省 createtime/updatetime 在此补齐（对齐 DepositFlow 实体）。
class DepositDao {
  DepositDao._();

  static final DepositDao instance = DepositDao._();

  final AppDatabase _db = AppDatabase.instance;

  /// 保存押金流水
  Future<void> saveDeposit(Map<String, dynamic> data) async {
    final Map<String, dynamic> row = Map<String, dynamic>.from(data);
    final String now =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    row.putIfAbsent('createtime', () => now);
    row.putIfAbsent('updatetime', () => now);
    await _db.insert('t_deposit_flow', row);
  }
}
