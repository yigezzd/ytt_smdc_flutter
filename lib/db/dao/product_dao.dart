import '../entity/db_table_name.dart';
import '../entity/product_bean_entity.dart';
import 'base_dao.dart';

/// 商品 DAO（对齐 ProductDao.kt）
///
/// 包含大量复杂 SQL（多表 JOIN / UNION / 日期过滤），
/// 所有查询均保留原项目 SQL 逻辑。
class ProductDao extends BaseDao<ProductBeanEntity> {
  ProductDao._();
  static final ProductDao instance = ProductDao._();

  @override
  String get table => DbTableName.tBiProduct;

  @override
  ProductBeanEntity fromMap(Map<String, dynamic> m) =>
      ProductBeanEntity.fromMap(m);

  // ──────────── 基础查询 ────────────

  /// 查询所有有效商品（员工端可见、未停用）
  Future<List<ProductBeanEntity>> queryAllType({int? spid}) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE status = 1 AND spid = ? '
      'AND mobileshowflag = 1 AND stopflag = 0 '
      'ORDER BY isort ASC, createtime DESC',
      [spid],
    );
    return rows.map(fromMap).toList();
  }

  /// 按 id 查询
  @override
  Future<ProductBeanEntity?> queryById(int id, {int? spid}) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE id = ? AND status = 1 AND spid = ? '
      'AND mobileshowflag = 1 AND stopflag = 0',
      [id, spid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按 productid 查询
  Future<ProductBeanEntity?> queryByProductId(String productid,
      {int? spid}) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE productid = ? AND status = 1 AND spid = ? '
      'AND mobileshowflag = 1 AND stopflag = 0',
      [productid, spid],
    );
    return row == null ? null : fromMap(row);
  }

  /// 按 productid 查询（套餐明细商品不过滤终端类型）
  Future<ProductBeanEntity?> queryByProductIdComb(String productid,
      {int? spid}) async {
    final row = await db.queryOne(
      'SELECT * FROM $table WHERE productid = ? AND status = 1 AND spid = ? '
      'AND stopflag = 0',
      [productid, spid],
    );
    return row == null ? null : fromMap(row);
  }

  // ──────────── 推荐菜 ────────────

  /// 查询推荐菜（含售卖日期过滤 + 分页）
  Future<List<ProductBeanEntity>> queryRecommend({
    required int spid,
    required int sid,
    required int week,
    required String month,
    int limit = 150,
    int offset = 0,
  }) async {
    final rows = await db.queryList(_buildDateFilterSql(
      baseWhere: 'recommendflag = 1 AND mobileshowflag = 1 AND spid = ? AND stopflag = 0',
      extraArgs: [spid],
      spid: spid,
      sid: sid,
      week: week,
      month: month,
      orderBy: 'isort ASC, createtime DESC',
      limit: limit,
      offset: offset,
    ));
    return rows.map(fromMap).toList();
  }

  // ──────────── 按分类查商品 ────────────

  /// 按分类 ID 查询商品（二级分类，含日期过滤 + 分页）
  Future<List<ProductBeanEntity>> queryPageProduct({
    required int spid,
    required int sid,
    required String typeId,
    required int week,
    required String month,
    int limit = 200,
    int offset = 0,
  }) async {
    final rows = await db.queryList(_buildDateFilterSql(
      baseWhere: 'typeid = ? AND mobileshowflag = 1 AND spid = ? AND stopflag = 0',
      extraArgs: [typeId, spid],
      spid: spid,
      sid: sid,
      week: week,
      month: month,
      orderBy: 'typeproisort ASC',
      limit: limit,
      offset: offset,
    ));
    return rows.map(fromMap).toList();
  }

  /// 按分类 ID（含子分类）查询商品（含日期过滤 + 分页）
  Future<List<ProductBeanEntity>> queryPageProductByType({
    required int spid,
    required int sid,
    required String id,
    required int week,
    required String month,
    int limit = 200,
    int offset = 0,
  }) async {
    final rows = await db.queryList(_buildDateFilterWithTypeJoinSql(
      id: id,
      spid: spid,
      sid: sid,
      week: week,
      month: month,
      limit: limit,
      offset: offset,
    ));
    return rows.map(fromMap).toList();
  }

  // ──────────── 按分类 ID 查（简化版） ────────────

  /// 按 typeid 前缀查询
  Future<List<ProductBeanEntity>> queryByTypeId(String typeid,
      {int? spid}) async {
    final rows = await db.queryList(
      'SELECT * FROM $table WHERE typeid LIKE ? || \'%\' AND stopflag = 0 '
      'AND status = 1 AND spid = ? AND mobileshowflag = 1 '
      'ORDER BY isort ASC, createtime DESC',
      [typeid, spid],
    );
    return rows.map(fromMap).toList();
  }

  // ──────────── 搜索 ────────────

  /// 按名称 / 检索码 / 条码搜索商品（含日期过滤 + 分页）
  Future<List<ProductBeanEntity>> queryByName({
    required String name,
    required int spid,
    required int sid,
    required int week,
    required String month,
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await db.queryList(_buildSearchSql(
      name: name,
      spid: spid,
      sid: sid,
      week: week,
      month: month,
      limit: limit,
      offset: offset,
    ));
    return rows.map(fromMap).toList();
  }

  // ──────────── 查找单个商品 ────────────

  /// 按 productid 查找商品（含日期过滤，不分页）
  Future<ProductBeanEntity?> findProduct({
    required String productid,
    required int spid,
    required int sid,
    required int week,
    required String month,
  }) async {
    final rows = await db.queryList(_buildDateFilterSql(
      baseWhere: 'productid = ? AND mobileshowflag = 1 AND spid = ? AND stopflag = 0',
      extraArgs: [productid, spid],
      spid: spid,
      sid: sid,
      week: week,
      month: month,
    ));
    return rows.isEmpty ? null : fromMap(rows.first);
  }

  // ──────────── 写操作 ────────────

  /// 重置所有记录的 stopflag 为 0
  Future<void> updateAll() async {
    await db.queryList("UPDATE $table SET stopflag = 0");
  }

  // ──────────── 内部 SQL 构建 ────────────
  
  /// 构建含售卖日期过滤的 UNION SQL（4 段 union：不限/日/周/月）
  ///
  /// 对齐 ProductDao.kt queryrecommend / queryPageProduct 的 SQL 结构：
  /// - 段1：不限日期 (saledateflag <= 1)
  /// - 段2-4：saledateflag <= 1 OR (日期过滤子查询 AND cycletype=N)
  String _buildDateFilterSql({
    required String baseWhere,
    required List<Object?> extraArgs,
    required int spid,
    required int sid,
    required int week,
    required String month,
    String orderBy = '',
    int? limit,
    int? offset,
  }) {
    final sb = StringBuffer();
    // 段1：不限日期
    sb.write('SELECT * FROM $table WHERE $baseWhere AND status = 1 AND saledateflag <= 1');
  
    // 段2-4：saledateflag<=1 OR (日期过滤子查询 AND cycletype=N)
    for (final cycleType in [1, 2, 3]) {
      sb.write(' UNION ');
      sb.write('SELECT * FROM $table WHERE $baseWhere AND status = 1 '
          'AND saledateflag <= 1 '
          'OR (stopflag = 0 AND status = 1 AND saledateflag = 2 AND '
          'productid IN (SELECT productid FROM ${DbTableName.tBiProductDate} p '
          'WHERE p.spid = ? AND p.sid = ? AND p.status = 1 AND p.stopflag = 0 '
          'AND p.mobileshowflag = 1 AND p.recommendflag = 1 AND '
          "strftime('%Y-%m-%d', 'now') >= COALESCE(strftime('%Y-%m-%d', p.begindate), strftime('%Y-%m-%d', 'now')) "
          "AND strftime('%Y-%m-%d', 'now') <= COALESCE(strftime('%Y-%m-%d', p.enddate), strftime('%Y-%m-%d', 'now'))");
      if (cycleType == 1) {
        sb.write(' AND cycletype = 1');
      } else if (cycleType == 2) {
        sb.write(" AND cycletype = 2 AND (SUBSTR(p.saleweek, ?, 1) = '1')");
      } else {
        sb.write(" AND cycletype = 3 AND ',' || p.salemonth || ',' LIKE '%,' || ? || ',%'");
      }
      sb.write('))');
    }
  
    if (orderBy.isNotEmpty) {
      sb.write(' ORDER BY $orderBy');
    }
    if (limit != null) {
      sb.write(' LIMIT $limit');
      if (offset != null) {
        sb.write(' OFFSET $offset');
      }
    }
    return sb.toString();
  }
  
  /// 构建含 t_bi_type JOIN 的 UNION SQL（按分类 code 前缀匹配）
  ///
  /// 对齐 ProductDao.kt queryPageProductByType1 的 SQL 结构。
  String _buildDateFilterWithTypeJoinSql({
    required String id,
    required int spid,
    required int sid,
    required int week,
    required String month,
    int limit = 200,
    int offset = 0,
  }) {
    final sb = StringBuffer();
    const typeFilter = "(t.code = ? OR t.code LIKE ? || '%')";
  
    // 段1：不限日期
    sb.write('SELECT p.* FROM $table p '
        'INNER JOIN ${DbTableName.tBiType} t ON p.typeid = t.typeid AND p.spid = t.spid '
        'AND t.status = 1 AND t.mobileshowflag = 1 WHERE '
        'p.mobileshowflag = 1 AND p.spid = ? AND p.stopflag = 0 AND p.status = 1 '
        'AND p.saledateflag <= 1 AND $typeFilter');
  
    // 段2-4：saledateflag<=1 OR (日期过滤子查询 AND cycletype=N)
    for (final cycleType in [1, 2, 3]) {
      sb.write(' UNION ');
      sb.write('SELECT p.* FROM $table p '
          'INNER JOIN ${DbTableName.tBiType} t ON p.typeid = t.typeid AND p.spid = t.spid '
          'AND t.status = 1 AND t.mobileshowflag = 1 WHERE '
          'p.mobileshowflag = 1 AND p.spid = ? AND p.stopflag = 0 AND p.status = 1 '
          'AND $typeFilter '
          'AND (p.saledateflag <= 1 OR (p.stopflag = 0 AND p.status = 1 AND p.saledateflag = 2 AND '
          'p.productid IN (SELECT productid FROM ${DbTableName.tBiProductDate} d '
          'WHERE d.spid = ? AND d.status = 1 AND p.status = 1 AND d.sid = ? '
          'AND p.stopflag = 0 AND p.mobileshowflag = 1 AND '
          "strftime('%Y-%m-%d', 'now') >= COALESCE(strftime('%Y-%m-%d', d.begindate), strftime('%Y-%m-%d', 'now')) "
          "AND strftime('%Y-%m-%d', 'now') <= COALESCE(strftime('%Y-%m-%d', d.enddate), strftime('%Y-%m-%d', 'now'))");
      if (cycleType == 1) {
        sb.write(' AND p.cycletype = 1');
      } else if (cycleType == 2) {
        sb.write(" AND p.cycletype = 2 AND (SUBSTR(d.saleweek, ?, 1) = '1')");
      } else {
        sb.write(" AND p.cycletype = 3 AND ',' || d.salemonth || ',' LIKE '%,' || ? || ',%'");
      }
      sb.write(')))');
    }
  
    sb.write(' ORDER BY p.isort ASC, p.createtime DESC LIMIT $limit OFFSET $offset');
    return sb.toString();
  }
  
  /// 构建搜索 SQL（按名称/检索码/条码搜索，含分类过滤 + 日期过滤）
  ///
  /// 对齐 ProductDao.kt queryByName 的 SQL 结构。
  String _buildSearchSql({
    required String name,
    required int spid,
    required int sid,
    required int week,
    required String month,
    int limit = 20,
    int offset = 0,
  }) {
    const nameFilter =
        "(name LIKE '%' || ? || '%' OR helpcode LIKE '%' || ? || '%' "
        "OR barcode LIKE '%' || ? || '%' OR code LIKE '%' || ? || '%')";
    const typeJoin = ' AND typeid IN ('
        'SELECT t.typeid FROM ${DbTableName.tBiType} t '
        'WHERE (t.typeid = p.typeid OR t.typeid LIKE p.typeid || \'%\') '
        'AND t.mobileshowflag = 1 AND t.stopflag = 0)';
  
    final sb = StringBuffer();
    // 段1：不限日期
    sb.write('SELECT * FROM $table p WHERE $nameFilter AND mobileshowflag = 1 '
        'AND spid = ? AND stopflag = 0 AND status = 1 AND saledateflag <= 1 $typeJoin');
    // 段2-4：saledateflag<=1 OR (日期过滤子查询 AND cycletype=N)
    for (final cycleType in [1, 2, 3]) {
      sb.write(' UNION ');
      sb.write('SELECT * FROM $table p WHERE $nameFilter AND mobileshowflag = 1 '
          'AND spid = ? AND stopflag = 0 $typeJoin AND status = 1 '
          'AND (saledateflag <= 1 OR (saledateflag = 2 AND '
          'productid IN (SELECT productid FROM ${DbTableName.tBiProductDate} p2 '
          'WHERE p2.status = 1 AND p2.spid = ? AND p2.sid = ? AND p2.mobileshowflag = 1 '
          'AND p2.stopflag = 0 AND '
          "strftime('%Y-%m-%d', 'now') >= COALESCE(strftime('%Y-%m-%d', p2.begindate), strftime('%Y-%m-%d', 'now')) "
          "AND strftime('%Y-%m-%d', 'now') <= COALESCE(strftime('%Y-%m-%d', p2.enddate), strftime('%Y-%m-%d', 'now'))");
      if (cycleType == 1) {
        sb.write(' AND p2.cycletype = 1');
      } else if (cycleType == 2) {
        sb.write(" AND p2.cycletype = 2 AND (SUBSTR(p2.saleweek, ?, 1) = '1')");
      } else {
        sb.write(" AND p2.cycletype = 3 AND ',' || p2.salemonth || ',' LIKE '%,' || ? || ',%'");
      }
      sb.write(')))');
    }
    sb.write(' LIMIT $limit OFFSET $offset');
    return sb.toString();
  }
}
