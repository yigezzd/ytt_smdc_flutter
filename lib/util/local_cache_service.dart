import 'dart:convert';

import 'package:flutter_deer/util/log_utils.dart';
import 'package:sp_util/sp_util.dart';

/// 本地数据缓存服务（对齐 smdcapp Room 数据库核心缓存表）
///
/// 提供关键业务数据的本地缓存能力，支持弱网/离线场景下的数据读取。
/// 对齐 smdcapp 的 Room 数据库核心表：
/// - t_bi_product（商品缓存）
/// - t_bi_type（分类缓存）
/// - t_table_info（桌台缓存）
/// - t_bi_payway（支付方式缓存）
/// - sys_parameter（系统参数）
///
/// 注意：当前使用 SharedPreferences(sp_util) 实现轻量级缓存。
/// 如需完整离线数据库能力，建议后续引入 sqflite/drift 迁移。
class LocalCacheService {
  LocalCacheService._();
  static final LocalCacheService instance = LocalCacheService._();

  // ──────────── 缓存 Key 前缀 ─────────────────────────────────────────

  static const String _prefixProduct = 'cache_product_';
  static const String _prefixCategory = 'cache_category_';
  static const String _prefixTable = 'cache_table_';
  static const String _prefixPayway = 'cache_payway_';
  static const String _keyProductList = 'cache_product_list';
  static const String _keyCategoryList = 'cache_category_list';
  static const String _keyTableList = 'cache_table_list';
  static const String _keyPaywayList = 'cache_payway_list';

  // ──────────── 商品缓存（对齐 smdcapp t_bi_product）─────────────────

  /// 缓存商品列表
  void cacheProducts(List<Map<String, dynamic>> products) {
    try {
      SpUtil.putString(_keyProductList, jsonEncode(products));
    } catch (e) {
      Log.e('LocalCacheService.cacheProducts error: $e');
    }
  }

  /// 读取缓存的商品列表
  List<Map<String, dynamic>> getCachedProducts() {
    return _readList(_keyProductList);
  }

  /// 按ID读取缓存的商品
  Map<String, dynamic>? getCachedProduct(String productid) {
    final List<Map<String, dynamic>> products = getCachedProducts();
    for (final Map<String, dynamic> p in products) {
      if (p['productid']?.toString() == productid) return p;
    }
    return null;
  }

  // ──────────── 分类缓存（对齐 smdcapp t_bi_type）─────────────────

  /// 缓存分类列表
  void cacheCategories(List<Map<String, dynamic>> categories) {
    try {
      SpUtil.putString(_keyCategoryList, jsonEncode(categories));
    } catch (e) {
      Log.e('LocalCacheService.cacheCategories error: $e');
    }
  }

  /// 读取缓存的分类列表
  List<Map<String, dynamic>> getCachedCategories() {
    return _readList(_keyCategoryList);
  }

  // ──────────── 桌台缓存（对齐 smdcapp t_table_info）─────────────────

  /// 缓存桌台列表
  void cacheTables(List<Map<String, dynamic>> tables) {
    try {
      SpUtil.putString(_keyTableList, jsonEncode(tables));
    } catch (e) {
      Log.e('LocalCacheService.cacheTables error: $e');
    }
  }

  /// 读取缓存的桌台列表
  List<Map<String, dynamic>> getCachedTables() {
    return _readList(_keyTableList);
  }

  // ──────────── 支付方式缓存（对齐 smdcapp t_bi_payway）─────────────────

  /// 缓存支付方式列表
  void cachePayways(List<Map<String, dynamic>> payways) {
    try {
      SpUtil.putString(_keyPaywayList, jsonEncode(payways));
    } catch (e) {
      Log.e('LocalCacheService.cachePayways error: $e');
    }
  }

  /// 读取缓存的支付方式列表
  List<Map<String, dynamic>> getCachedPayways() {
    return _readList(_keyPaywayList);
  }

  // ──────────── 通用方法 ─────────────────────────────────────────

  /// 读取列表缓存
  List<Map<String, dynamic>> _readList(String key) {
    try {
      final String raw = SpUtil.getString(key) ?? '';
      if (raw.isEmpty) return [];
      final dynamic data = jsonDecode(raw);
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList();
      }
      return [];
    } catch (e) {
      Log.e('LocalCacheService._readList error: $e');
      return [];
    }
  }

  /// 清空所有缓存（退出登录时调用，对齐 smdcapp 数据清空）
  void clearAll() {
    SpUtil.remove(_keyProductList);
    SpUtil.remove(_keyCategoryList);
    SpUtil.remove(_keyTableList);
    SpUtil.remove(_keyPaywayList);
  }

  /// 检查是否有有效缓存
  bool get hasCache {
    return (SpUtil.getString(_keyProductList) ?? '').isNotEmpty ||
        (SpUtil.getString(_keyTableList) ?? '').isNotEmpty;
  }
}
