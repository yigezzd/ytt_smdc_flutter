import '../entity/db_table_name.dart';
import '../entity/vip_type_entity.dart';
import 'base_dao.dart';

/// 会员分类 DAO（对齐 smdcapp VipTypeDao.kt）
class VipTypeDao extends BaseDao<VipTypeEntity> {
  VipTypeDao._();
  static final VipTypeDao instance = VipTypeDao._();

  @override
  String get table => DbTableName.tVipType;

  @override
  VipTypeEntity fromMap(Map<String, dynamic> m) => VipTypeEntity.fromMap(m);

  /// 按 typeid 查询会员分类
  Future<VipTypeEntity?> getByTypeid(String typeid) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE typeid = ?',
      [typeid],
    );
    return row == null ? null : fromMap(row);
  }
}
