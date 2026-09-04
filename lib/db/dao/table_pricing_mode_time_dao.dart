import '../entity/db_table_name.dart';
import '../entity/table_pricing_mode_time_entity.dart';
import 'base_dao.dart';

/// 桌台区间收费 DAO（对齐 TablePricingModeTimeDao.kt）
class TablePricingModeTimeDao
    extends BaseDao<TablePricingModeTimeEntity> {
  TablePricingModeTimeDao._();
  static final TablePricingModeTimeDao instance =
      TablePricingModeTimeDao._();

  @override
  String get table => DbTableName.tTablePricingmodeTime;

  @override
  TablePricingModeTimeEntity fromMap(Map<String, dynamic> m) =>
      TablePricingModeTimeEntity.fromMap(m);

  /// 按桌台类型查询区间收费
  Future<List<TablePricingModeTimeEntity>> query({
    required String tabletypeid,
    required int spid,
    required int sid,
  }) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND sid = ? '
      'AND tabletypeid = ? AND status = 1',
      [spid, sid, tabletypeid],
    );
    return rows.map(fromMap).toList();
  }
}
