import '../entity/db_table_name.dart';
import '../entity/product_type_entity.dart';
import 'base_dao.dart';

/// 商品分类 DAO（对齐 ProductTypeDao.kt）
class ProductTypeDao extends BaseDao<ProductTypeEntity> {
  ProductTypeDao._();
  static final ProductTypeDao instance = ProductTypeDao._();

  @override
  String get table => DbTableName.tBiType;

  @override
  ProductTypeEntity fromMap(Map<String, dynamic> m) =>
      ProductTypeEntity.fromMap(m);

  /// 查询所有有效分类（员工端可见、未停用）
  Future<List<ProductTypeEntity>> queryAllType({int? spid}) async {
    String sql =
        'SELECT * FROM $table WHERE spid = ? AND stopflag = 0 AND status = 1 '
        'AND mobileshowflag = 1 ORDER BY isort ASC, createtime DESC';
    final args = <Object?>[spid];
    final rows = await db.queryList(sql, args);
    return rows.map(fromMap).toList();
  }

  /// 按 typeid 查询
  Future<ProductTypeEntity?> queryByTypeId(String typeid, {int? spid}) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE typeid = ? AND spid = ? '
      'AND stopflag = 0 AND status = 1 AND mobileshowflag = 1 '
      'ORDER BY isort ASC, createtime DESC',
      [typeid, spid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按 typeid 查询（套餐明细商品不过滤终端类型）
  Future<ProductTypeEntity?> queryByTypeIdComb(String typeid,
      {int? spid}) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE typeid = ? AND spid = ? '
      'AND stopflag = 0 AND status = 1',
      [typeid, spid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 查询所有一级分类
  Future<List<ProductTypeEntity>> queryAllLevel1({int? spid}) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE level = 1 AND spid = ? '
      'AND stopflag = 0 AND status = 1 AND mobileshowflag = 1 '
      'ORDER BY isort ASC, createtime DESC',
      [spid],
    );
    return rows.map(fromMap).toList();
  }

  /// 根据一级分类查询对应的二级子分类
  Future<List<ProductTypeEntity>> queryAllLevel2ByTypeid(String typeid,
      {int? spid}) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE level = 2 AND parenttypeid LIKE ? || \'%\' '
      'AND spid = ? AND stopflag = 0 AND status = 1 AND mobileshowflag = 1 '
      'ORDER BY isort ASC, createtime DESC',
      [typeid, spid],
    );
    return rows.map(fromMap).toList();
  }

  /// 查询全部二级子分类
  Future<List<ProductTypeEntity>> queryAllLevel2({int? spid}) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE level = 2 AND spid = ? '
      'AND stopflag = 0 AND status = 1 AND mobileshowflag = 1 '
      'ORDER BY isort ASC, createtime DESC',
      [spid],
    );
    return rows.map(fromMap).toList();
  }

  /// 查询所有（PC端可见）
  Future<List<ProductTypeEntity>> queryAllPc({int? spid}) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE spid = ? AND stopflag = 0 AND status = 1 '
      'AND pcshowflag = 1 ORDER BY isort ASC, createtime DESC',
      [spid],
    );
    return rows.map(fromMap).toList();
  }
}
