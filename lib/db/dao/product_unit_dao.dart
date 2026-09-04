import '../entity/db_table_name.dart';
import '../entity/product_unit_entity.dart';
import 'base_dao.dart';

/// 商品单位 DAO（对齐 ProductUnitDao.kt）
class ProductUnitDao extends BaseDao<ProductUnitEntity> {
  ProductUnitDao._();
  static final ProductUnitDao instance = ProductUnitDao._();

  @override
  String get table => DbTableName.tBiUnit;

  @override
  ProductUnitEntity fromMap(Map<String, dynamic> m) =>
      ProductUnitEntity.fromMap(m);

  /// 重置所有记录的 stopflag 为 0
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET stopflag = 0");
  }
}
