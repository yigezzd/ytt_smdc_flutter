import '../entity/db_table_name.dart';
import '../entity/pay_way_info_entity.dart';
import 'base_dao.dart';

/// 支付方式 DAO（对齐 PayWayDao.kt）
class PayWayInfoDao extends BaseDao<PayWayInfoEntity> {
  PayWayInfoDao._();
  static final PayWayInfoDao instance = PayWayInfoDao._();

  @override
  String get table => DbTableName.tBiPayway;

  @override
  PayWayInfoEntity fromMap(Map<String, dynamic> m) =>
      PayWayInfoEntity.fromMap(m);

  /// 按 payid 查询
  Future<PayWayInfoEntity?> queryByPayid(String payid) async {
    return queryByColumn('payid', payid);
  }

  /// 重置所有记录的 stopflag 为 0
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET stopflag = 0");
  }
}
