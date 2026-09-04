import '../entity/db_table_name.dart';
import '../entity/product_spec_entity.dart';
import 'base_dao.dart';

/// 商品规格关联 DAO（对齐 ProductSpecDao.kt）
class ProductSpecDao extends BaseDao<ProductSpecEntity> {
  ProductSpecDao._();
  static final ProductSpecDao instance = ProductSpecDao._();

  @override
  String get table => DbTableName.tBiProductSpec;

  @override
  ProductSpecEntity fromMap(Map<String, dynamic> m) =>
      ProductSpecEntity.fromMap(m);

  /// 查询规格详情（联表 t_bi_spec，优先查分店）
  Future<List<ProductSpecEntity>> querySpecInfo({
    required int spid,
    required int sid,
    required String productid,
  }) async {
    final rows = await db.queryList(
      'SELECT a.*, b.name AS specname '
      'FROM ${DbTableName.tBiProductSpec} a, ${DbTableName.tBiSpec} b '
      'WHERE a.spid = b.spid AND a.specid = b.specid '
      'AND a.spid = ? AND a.sid = ? AND a.productid = ? '
      'AND a.status = 1 AND b.status = 1 AND b.stopflag = 0 '
      'ORDER BY a.id ASC',
      [spid, sid, productid],
    );
    return rows.map(fromMap).toList();
  }

  /// 查询规格详情（仅按 spid，不过滤 sid）
  Future<List<ProductSpecEntity>> querySpecInfoSpid({
    required int spid,
    required String productid,
  }) async {
    final rows = await db.queryList(
      'SELECT a.*, b.name AS specname '
      'FROM ${DbTableName.tBiProductSpec} a, ${DbTableName.tBiSpec} b '
      'WHERE a.spid = b.spid AND a.specid = b.specid '
      'AND a.spid = ? AND a.productid = ? '
      'AND a.status = 1 AND b.status = 1 AND b.stopflag = 0 '
      'ORDER BY a.id ASC',
      [spid, productid],
    );
    return rows.map(fromMap).toList();
  }

  /// 按 productid + specid 查询（不校验 spec 表停用状态）
  Future<ProductSpecEntity?> queryBySpecid({
    required String productid,
    required String specid,
    required int spid,
    required int sid,
  }) async {
    final row = await db.queryOne(
      'SELECT a.*, b.name AS specname '
      'FROM ${DbTableName.tBiProductSpec} a, ${DbTableName.tBiSpec} b '
      'WHERE a.spid = b.spid AND a.specid = b.specid '
      'AND a.spid = ? AND a.sid = ? AND a.productid = ? AND a.specid = ? '
      'AND a.status = 1',
      [spid, sid, productid, specid],
    );
    return row == null ? null : fromMap(row);
  }
}
