import '../entity/db_table_name.dart';
import '../entity/must_product_entity.dart';
import 'base_dao.dart';

/// 必点菜商品 DAO（对齐 MustProductDao.kt）
class MustProductDao extends BaseDao<MustProductEntity> {
  MustProductDao._();
  static final MustProductDao instance = MustProductDao._();

  @override
  String get table => DbTableName.tMustProduct;

  @override
  MustProductEntity fromMap(Map<String, dynamic> m) =>
      MustProductEntity.fromMap(m);

  /// 按 spid + sid 查询所有
  Future<List<MustProductEntity>> queryAllBySpidSid({
    required int spid,
    required int sid,
  }) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND sid = ?',
      [spid, sid],
    );
    return rows.map(fromMap).toList();
  }

  /// 按 billid 查询必点菜商品（联表 t_bi_product）
  Future<List<Map<String, dynamic>>> queryByBillid({
    required int spid,
    String billid = '',
  }) async {
    return db.queryList(
      'SELECT a.*, b.* FROM ${DbTableName.tMustProduct} a '
      'INNER JOIN ${DbTableName.tBiProduct} b ON '
      'a.spid = b.spid AND a.productid = b.productid '
      'AND b.status = 1 AND b.mobileshowflag = 1 '
      'WHERE a.spid = ? AND a.billid = ?',
      [spid, billid],
    );
  }
}
