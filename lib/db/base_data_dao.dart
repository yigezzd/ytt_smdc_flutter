import 'app_database.dart';

/// 基础数据写入 DAO（对齐 YttPhone：t_bi_payway/t_bi_payway_store/
/// t_bi_type/t_bi_parameter）
///
/// 登录成功后由 CashReconService.syncBaseData 调用：先清空再全量重写，
/// 供交班统计 SQL 关联支付方式表/分类表使用。
class BaseDataDao {
  BaseDataDao._();

  static final BaseDataDao instance = BaseDataDao._();

  final AppDatabase _db = AppDatabase.instance;

  /// 全量重写支付方式（getPayInfoList 响应 list）
  ///
  /// 同一份数据同时写 t_bi_payway（PayWayInfo）与 t_bi_payway_store
  /// （PaywayStore），多余字段由通用 insert 自动忽略。
  Future<void> savePayways(List<Map<String, dynamic>> list) async {
    if (list.isEmpty) {
      return;
    }
    await _db.clearTable('t_bi_payway');
    await _db.clearTable('t_bi_payway_store');
    await _db.batchInsert('t_bi_payway', list);
    await _db.batchInsert('t_bi_payway_store', list);
  }

  /// 全量重写商品分类（getTypeList 响应 data.children）
  Future<void> saveTypes(List<Map<String, dynamic>> list) async {
    if (list.isEmpty) {
      return;
    }
    await _db.clearTable('t_bi_type');
    await _db.batchInsert('t_bi_type', list);
  }

  /// 全量重写参数表（交班开关当前值，code=开关名/remark=machno）
  Future<void> saveParameters(List<Map<String, dynamic>> list) async {
    if (list.isEmpty) {
      return;
    }
    await _db.clearTable('t_bi_parameter');
    await _db.batchInsert('t_bi_parameter', list);
  }

  /// t_bi_payway 是否为空（交班查询时为空则自动重试一次同步）
  Future<bool> isPaywayEmpty() async {
    final List<Map<String, dynamic>> rows =
        await _db.queryList('select count(1) as cnt from t_bi_payway');
    final int cnt = rows.isEmpty
        ? 0
        : int.tryParse(rows.first['cnt']?.toString() ?? '') ?? 0;
    return cnt == 0;
  }
}
