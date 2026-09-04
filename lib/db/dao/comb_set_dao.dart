import '../entity/db_table_name.dart';
import '../entity/product_comb_set_entity.dart';
import 'base_dao.dart';

/// 套餐明细 DAO（对齐 CombSetDao.kt）
class CombSetDao extends BaseDao<ProductCombSetEntity> {
  CombSetDao._();
  static final CombSetDao instance = CombSetDao._();

  @override
  String get table => DbTableName.tBiCombSet;

  @override
  ProductCombSetEntity fromMap(Map<String, dynamic> m) =>
      ProductCombSetEntity.fromMap(m);

  /// 查询所有套餐分组（按 groupid 去重）
  Future<List<ProductCombSetEntity>> queryAllGroup({
    required String productid,
    required int spid,
    required int sid,
  }) async {
    final rows = await db.queryList(
      'SELECT groupid, groupname, repeatflag, selectqty, spid, sid, defflag, '
      'combid, productid, productname, price, qty, status, isort, stopflag, '
      'specid, barcode, unit, size, createtime, updatetime, operid, addprice, '
      'cutprice, opername, selecttype, min(id) AS id '
      'FROM $table WHERE spid = ? AND sid = ? AND status = 1 '
      'AND stopflag = 0 AND combid = ? '
      'GROUP BY groupid, groupname, repeatflag, selectqty '
      'ORDER BY isort, id',
      [spid, sid, productid],
    );
    return rows.map(fromMap).toList();
  }

  /// 根据套餐分组查询明细
  Future<List<ProductCombSetEntity>> queryAllInfo({
    required int spid,
    required int sid,
    required String groupid,
    required String combid,
  }) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND sid = ? AND status = 1 '
      'AND groupid = ? AND combid = ?',
      [spid, sid, groupid, combid],
    );
    return rows.map(fromMap).toList();
  }

  /// 查询套餐明细指定商品配置信息
  Future<ProductCombSetEntity?> queryGroupInfo({
    required String combid,
    required String productid,
    required int spid,
    required int sid,
  }) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE spid = ? AND sid = ? AND status = 1 '
      'AND groupid = ? AND productid = ?',
      [spid, sid, combid, productid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 重置所有记录的 status 为 1
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET status = 1");
  }
}
