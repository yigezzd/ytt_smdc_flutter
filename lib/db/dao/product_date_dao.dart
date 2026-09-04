import '../entity/db_table_name.dart';
import '../entity/product_date_entity.dart';
import 'base_dao.dart';

/// 商品售卖日期 DAO（对齐 ProductDateDao.kt）
class ProductDateDao extends BaseDao<ProductDateEntity> {
  ProductDateDao._();
  static final ProductDateDao instance = ProductDateDao._();

  @override
  String get table => DbTableName.tBiProductDate;

  @override
  ProductDateEntity fromMap(Map<String, dynamic> m) =>
      ProductDateEntity.fromMap(m);

  /// 重置所有记录的 stopflag 为 0
  Future<void> updateAll() async {
    await db.queryList(
        "UPDATE $table SET stopflag = 0");
  }
}
