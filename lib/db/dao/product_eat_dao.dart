import '../entity/db_table_name.dart';
import '../entity/product_eat_entity.dart';
import 'base_dao.dart';

/// 商品吃法关联 DAO（对齐 ProductEatDao.kt）
class ProductEatDao extends BaseDao<ProductEatEntity> {
  ProductEatDao._();
  static final ProductEatDao instance = ProductEatDao._();

  @override
  String get table => DbTableName.tProductEat;

  @override
  ProductEatEntity fromMap(Map<String, dynamic> m) =>
      ProductEatEntity.fromMap(m);

  /// 根据商品ID查询该商品所有的专属加价做法
  Future<List<ProductEatEntity>> getEatListByProduct(String productId) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE productid = ? AND status = 1',
      [productId],
    );
    return rows.map(fromMap).toList();
  }

  /// 通过商品ID联表查询分组+做法+专属加价（打平结果）
  Future<List<Map<String, dynamic>>> getRawProductEatList({
    required String productId,
    required int spid,
    required int sid,
  }) async {
    return db.queryList(
      'SELECT g.id AS g_id, g.spid AS g_spid, g.sid AS g_sid, '
      'g.groupid AS g_groupid, g.name AS g_name, g.status AS g_status, '
      'g.gisort AS g_gisort, g.createtime AS g_createtime, '
      'g.updatetime AS g_updatetime, g.operid AS g_operid, '
      'g.opername AS g_opername, i.*, pe.price AS sellprice, '
      'pe.defrecommend AS defrecommend '
      'FROM ${DbTableName.tEatGroup} g '
      'INNER JOIN ${DbTableName.tProductEat} pe ON g.groupid = pe.groupid '
      'INNER JOIN ${DbTableName.tEatInfo} i ON pe.eatcode = i.code '
      'WHERE pe.productid = ? AND pe.spid = ? AND pe.sid = ? '
      'AND pe.status = 1 AND g.status = 1 AND i.status = 1 AND i.stopflag = 0 '
      'ORDER BY g.gisort ASC, i.groupisort ASC',
      [productId, spid, sid],
    );
  }

  /// 获取公共通用做法（打平结果）
  Future<List<Map<String, dynamic>>> getPublicEatList({
    required int spid,
    required int sid,
  }) async {
    return db.queryList(
      'SELECT g.id AS g_id, g.spid AS g_spid, g.sid AS g_sid, '
      'g.groupid AS g_groupid, g.name AS g_name, g.status AS g_status, '
      'g.gisort AS g_gisort, g.createtime AS g_createtime, '
      'g.updatetime AS g_updatetime, g.operid AS g_operid, '
      'g.opername AS g_opername, i.*, i.price AS sellprice, '
      '0 AS defrecommend '
      'FROM ${DbTableName.tEatGroup} g '
      'INNER JOIN ${DbTableName.tEatInfo} i ON g.groupid = i.groupid '
      'WHERE g.status = 1 AND i.status = 1 AND i.stopflag = 0 '
      'AND g.spid = ? AND g.sid = ? '
      'ORDER BY g.gisort ASC, i.groupisort ASC',
      [spid, sid],
    );
  }
}
