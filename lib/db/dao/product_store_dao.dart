import '../entity/db_table_name.dart';
import '../entity/product_store_entity.dart';
import 'base_dao.dart';

/// 商品门店价格 DAO（对齐 smdcapp ProductStoreDao.kt）
class ProductStoreDao extends BaseDao<ProductStoreEntity> {
  ProductStoreDao._();
  static final ProductStoreDao instance = ProductStoreDao._();

  @override
  String get table => DbTableName.tBiProductStore;

  @override
  ProductStoreEntity fromMap(Map<String, dynamic> m) =>
      ProductStoreEntity.fromMap(m);

  /// 重置所有记录的 status 为 1
  Future<void> updateAll() async {
    await db.queryList('UPDATE $table SET status = 1');
  }
}
