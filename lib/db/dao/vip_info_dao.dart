import '../entity/db_table_name.dart';
import '../entity/vip_info_entity.dart';
import 'base_dao.dart';

/// 会员信息 DAO（对齐 smdcapp VipInfoDao.kt）
class VipInfoDao extends BaseDao<VipInfoEntity> {
  VipInfoDao._();
  static final VipInfoDao instance = VipInfoDao._();

  @override
  String get table => DbTableName.tVipInfo;

  @override
  VipInfoEntity fromMap(Map<String, dynamic> m) => VipInfoEntity.fromMap(m);

  /// 按 vipid 查询会员
  Future<VipInfoEntity?> getByVipid(String vipid) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE vipid = ?',
      [vipid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按手机号查询会员
  Future<VipInfoEntity?> getByMobile(String mobile) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE mobile = ?',
      [mobile],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按会员卡号查询会员
  Future<VipInfoEntity?> getByVipno(String vipno) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE vipno = ?',
      [vipno],
    );
    return row == null ? null : fromMap(row);
  }
}
