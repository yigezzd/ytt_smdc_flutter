import '../entity/db_table_name.dart';
import '../entity/mp_rule_entity.dart';
import 'base_dao.dart';

/// 促销规则 DAO（对齐 MPRuleDao.kt）
class MpRuleDao extends BaseDao<MpRuleEntity> {
  MpRuleDao._();
  static final MpRuleDao instance = MpRuleDao._();

  @override
  String get table => DbTableName.tMpPtRule;

  @override
  MpRuleEntity fromMap(Map<String, dynamic> m) => MpRuleEntity.fromMap(m);

  /// 满减规则：按 amt 降序取第一条满足条件的
  Future<MpRuleEntity?> selectAmt6({
    required int spid,
    required int sid,
    required String billid,
    required double amt,
  }) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE spid = ? AND sid = ? AND billid = ? '
      'AND amt <= ? ORDER BY amt DESC LIMIT 1',
      [spid, sid, billid, amt],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按 amt 升序取第一条
  Future<MpRuleEntity?> selectAmt({
    required int spid,
    required String billid,
    required double amt,
  }) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE spid = ? AND billid = ? '
      'AND amt <= ? ORDER BY amt ASC LIMIT 1',
      [spid, billid, amt],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按 qty 升序取第一条
  Future<MpRuleEntity?> selectQty({
    required int spid,
    required String billid,
    required double qty,
  }) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE spid = ? AND billid = ? '
      'AND qty <= ? ORDER BY qty ASC LIMIT 1',
      [spid, billid, qty],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按 billid 查询所有规则（spid + sid）
  Future<List<MpRuleEntity>> queryAllBySpidSid({
    required int spid,
    required int sid,
  }) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND sid = ?',
      [spid, sid],
    );
    return rows.map(fromMap).toList();
  }

  /// 按 spid + billid 取第一条规则（无 amt/qty 条件，对齐 select）
  Future<MpRuleEntity?> select({
    required int spid,
    required String billid,
  }) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE spid = ? AND billid = ? LIMIT 1',
      [spid, billid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按多个 billid 批量查询
  Future<List<MpRuleEntity>> byBillids({
    required List<String> billids,
    required int spid,
    required int sid,
  }) async {
    if (billids.isEmpty) {
      return [];
    }
    final placeholders = billids.map((_) => '?').join(',');
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND sid = ? AND billid IN ($placeholders)',
      [spid, sid, ...billids],
    );
    return rows.map(fromMap).toList();
  }
}
