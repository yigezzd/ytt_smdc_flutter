import '../entity/db_table_name.dart';
import '../entity/mp_store_entity.dart';
import 'base_dao.dart';

/// 促销活动门店 DAO（对齐 MPStoreDao.kt）
class MpStoreDao extends BaseDao<MpStoreEntity> {
  MpStoreDao._();
  static final MpStoreDao instance = MpStoreDao._();

  @override
  String get table => DbTableName.tMpStore;

  @override
  MpStoreEntity fromMap(Map<String, dynamic> m) => MpStoreEntity.fromMap(m);
}
