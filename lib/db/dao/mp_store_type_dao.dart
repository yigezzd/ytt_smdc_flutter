import '../entity/db_table_name.dart';
import '../entity/mp_store_type_entity.dart';
import 'base_dao.dart';

/// 促销活动可用分类 DAO（对齐 MPStoreTypeDao.kt）
class MpStoreTypeDao extends BaseDao<MpStoreTypeEntity> {
  MpStoreTypeDao._();
  static final MpStoreTypeDao instance = MpStoreTypeDao._();

  @override
  String get table => DbTableName.tMpStoreType;

  @override
  MpStoreTypeEntity fromMap(Map<String, dynamic> m) =>
      MpStoreTypeEntity.fromMap(m);
}
