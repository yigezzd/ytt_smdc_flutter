/// 后台表字段宽松读取工具
///
/// 云端 tabledown 对空字段下发 null，落库时可能写成空串（历史数据），
/// SQLite 对数值列不转换非数字文本会按 TEXT 存储；
/// 实体 fromMap 用 `as int?` / `as num?` 强转会抛
/// "type 'String' is not a subtype of type 'int?'" 并导致整表读取失败。
/// 数值字段统一经此读取，兼容 int / double / String / 空值。
int readMapInt(dynamic v, [int def = 0]) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final String s = v.toString().trim();
  if (s.isEmpty) return def;
  return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? def;
}

double readMapDouble(dynamic v, [double def = 0.0]) {
  if (v == null) return def;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  final String s = v.toString().trim();
  if (s.isEmpty) return def;
  return double.tryParse(s) ?? def;
}
