import 'app_database.dart';

/// 结账流水写入 DAO（对齐 YttPhone SqlActuatorUtils + smdcapp saveFlowInDb）
///
/// 云端 saleflow 上传成功后双写本地 4 表：t_sale_master/t_sale_payway/
/// t_sale_detail/t_sale_cook，供交班页本地统计使用。
/// saleBean 结构与 settle_page 构建的完全一致，多余字段由通用 insert 自动忽略。
class SaleDao {
  SaleDao._();

  static final SaleDao instance = SaleDao._();

  final AppDatabase _db = AppDatabase.instance;

  /// 保存整单结账流水（4 表批量插入）
  ///
  /// [saleBean] 为 saleflow 上传参数中的单条数据：含
  /// t_sale_master（单元素列表）/t_sale_detail/t_sale_payway/t_sale_cook。
  Future<void> saveSaleFlow(Map<String, dynamic> saleBean) async {
    final dynamic rawMaster = saleBean['t_sale_master'];
    final List<Map<String, dynamic>> masterList = rawMaster is List
        ? rawMaster.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> detailList = _toRows(saleBean['t_sale_detail']);
    final List<Map<String, dynamic>> paywayList = _toRows(saleBean['t_sale_payway']);
    final List<Map<String, dynamic>> cookList = _toRows(saleBean['t_sale_cook']);

    if (masterList.isNotEmpty) {
      await _db.batchInsert('t_sale_master', masterList);
    }
    if (detailList.isNotEmpty) {
      await _db.batchInsert('t_sale_detail', detailList);
    }
    if (paywayList.isNotEmpty) {
      await _db.batchInsert('t_sale_payway', paywayList);
    }
    if (cookList.isNotEmpty) {
      await _db.batchInsert('t_sale_cook', cookList);
    }
  }

  /// 容错转换：仅保留 Map 元素
  List<Map<String, dynamic>> _toRows(dynamic raw) {
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }
    return raw.whereType<Map<String, dynamic>>().toList();
  }
}
