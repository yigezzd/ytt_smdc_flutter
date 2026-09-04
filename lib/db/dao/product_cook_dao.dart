import '../entity/db_table_name.dart';
import '../entity/product_cook_entity.dart';
import 'base_dao.dart';

/// 商品做法 DAO（对齐 ProductCookDao.kt）
class ProductCookDao extends BaseDao<ProductCookEntity> {
  ProductCookDao._();
  static final ProductCookDao instance = ProductCookDao._();

  @override
  String get table => DbTableName.tProductCook;

  @override
  ProductCookEntity fromMap(Map<String, dynamic> m) =>
      ProductCookEntity.fromMap(m);

  /// 查询商品做法详情（联表 t_cook_info + t_cook_group）
  Future<List<ProductCookEntity>> queryCookInfo({
    required int spid,
    required int sid,
    required String productid,
  }) async {
    final rows = await db.queryList(
      'SELECT a.id, a.spid, a.sid, a.productid, a.groupid, a.cookcode, '
      'a.price, b.name AS cookname, c.name AS groupname, a.status, '
      'a.mandatoryflag, a.mandatoryqty, a.maximumflag, a.maximum, '
      'b.ptype, c.editqtyflag, b.cupstickercode, a.defrecommend '
      'FROM ${DbTableName.tProductCook} a, ${DbTableName.tCookInfo} b '
      'LEFT JOIN ${DbTableName.tCookGroup} c ON b.spid = c.spid '
      'AND b.groupid = c.groupid AND c.status = 1 '
      'WHERE a.spid = b.spid AND a.cookcode = b.code '
      'AND a.spid = ? AND a.sid = ? AND b.stopflag = 0 '
      'AND a.productid = ? AND a.status = 1 AND b.status = 1',
      [spid, sid, productid],
    );
    return rows.map(fromMap).toList();
  }

  /// 查询商品做法详情（不含加价做法，ptype=0）
  Future<List<ProductCookEntity>> queryCookInfoNoPrice({
    required int spid,
    required int sid,
    required String productid,
  }) async {
    final rows = await db.queryList(
      'SELECT a.id, a.spid, a.sid, a.productid, a.groupid, a.cookcode, '
      'a.price, b.name AS cookname, c.name AS groupname, a.status, '
      'a.mandatoryflag, a.mandatoryqty, a.maximumflag, a.maximum, '
      'b.ptype, c.editqtyflag, b.cupstickercode, a.defrecommend '
      'FROM ${DbTableName.tProductCook} a, ${DbTableName.tCookInfo} b '
      'LEFT JOIN ${DbTableName.tCookGroup} c ON b.spid = c.spid '
      'AND b.groupid = c.groupid AND c.status = 1 '
      'WHERE a.spid = b.spid AND a.cookcode = b.code '
      'AND a.spid = ? AND a.sid = ? AND b.stopflag = 0 '
      'AND a.productid = ? AND a.ptype = 0 AND a.status = 1 '
      'AND b.status = 1 AND b.stopflag = 0 AND b.ptype = 0',
      [spid, sid, productid],
    );
    return rows.map(fromMap).toList();
  }

  /// 查询全局做法（对齐 queryCookAll）
  ///
  /// JOIN cook_group + cook_info，返回打平结果
  Future<List<Map<String, dynamic>>> queryCookAll({
    required int spid,
    required int sid,
  }) async {
    const sql = 'SELECT '
        'c.id, c.spid, c.sid, c.groupid, '
        'b.code AS cookcode, b.price, b.name AS cookname, '
        'c.name AS groupname, c.status, '
        'b.ptype, c.editqtyflag, '
        'b.createtime, b.updatetime, b.operid, b.cupstickercode, b.opername '
        'FROM ${DbTableName.tCookGroup} c '
        'LEFT JOIN ${DbTableName.tCookInfo} b '
        'ON c.spid = b.spid AND b.groupid = c.groupid AND c.status = 1 '
        'WHERE c.spid = b.spid AND c.spid = ? AND c.sid = ? '
        'AND c.status = 1 AND b.status = 1 AND b.stopflag = 0';
    return db.queryList(sql, [spid, sid]);
  }

  /// 重置所有记录的 status 为 1
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET status = 1");
  }
}
