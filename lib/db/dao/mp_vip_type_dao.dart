import '../entity/db_table_name.dart';
import '../entity/mp_vip_type_entity.dart';
import 'base_dao.dart';

/// 促销活动VIP类型 DAO（对齐 MPVipTypeDao.kt）
class MpVipTypeDao extends BaseDao<MpVipTypeEntity> {
  MpVipTypeDao._();
  static final MpVipTypeDao instance = MpVipTypeDao._();

  @override
  String get table => DbTableName.tMpPtVipType;

  @override
  MpVipTypeEntity fromMap(Map<String, dynamic> m) =>
      MpVipTypeEntity.fromMap(m);

  /// 按 billid 查询
  Future<MpVipTypeEntity?> queryByBillid(String billid) async {
    return queryByColumn('billid', billid);
  }
}
