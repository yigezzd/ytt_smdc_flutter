import '../entity/db_table_name.dart';
import '../entity/mp_no_date_entity.dart';
import 'base_dao.dart';

/// 促销不可用日期 DAO（对齐 MPNoDateDao.kt）
class MpNoDateDao extends BaseDao<MpNoDateEntity> {
  MpNoDateDao._();
  static final MpNoDateDao instance = MpNoDateDao._();

  @override
  String get table => DbTableName.tMpPtNodate;

  @override
  MpNoDateEntity fromMap(Map<String, dynamic> m) => MpNoDateEntity.fromMap(m);
}
