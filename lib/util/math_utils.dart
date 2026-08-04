/// 精确数学运算工具类，解决浮点数精度问题
///
/// 移植自 boss 项目 [math.ts]，提供加、减、乘、除精确运算，
/// 避免 JavaScript/Dart 原生浮点运算产生的精度误差
/// （如：10.03 * 3445.67 → 34560.09999999998）。
///
/// 核心思路：
/// 1. 将操作数按小数位数放大为整数进行运算，再缩小回去
/// 2. [transferToNumber] 消除科学计数法
class MathUtils {
  MathUtils._();

  // =================== 精度辅助 ===================

  /// 获取数值的小数位数（基于字符串表示）
  ///
  /// ```dart
  /// MathUtils.getPrecision(1.23)   // 2
  /// MathUtils.getPrecision(100)    // 0
  /// MathUtils.getPrecision(0.001)  // 3
  /// ```
  static int getPrecision(num value) {
    final str = value.toString();
    final dotIndex = str.indexOf('.');
    if (dotIndex == -1) return 0;
    // 移除末尾可能的 'e' 科学计数法标记（极少见）
    final decimalPart = str.substring(dotIndex + 1);
    // 如果包含 'e'（如 1.23e-4），只取 'e' 之前的部分
    final eIndex = decimalPart.indexOf('e');
    if (eIndex != -1) return eIndex;
    return decimalPart.length;
  }

  /// 处理科学计数法，确保返回普通小数形式
  ///
  /// 对应 TypeScript `transferToNumber`：
  /// ```js
  /// let eformat = num.toExponential();
  /// let tmpArray = eformat.match(/\d(?:\.(\d*))?e([+-]\d+)/);
  /// let number = num.toFixed(Math.max(0, (tmpArray[1]||"").length - tmpArray[2]));
  /// ```
  static num transferToNumber(num value) {
    if (value.isNaN) return value;
    final str = value.toString();
    // Dart 只有在极小/极大时才用科学计数法（如 1.23e-7）
    if (!str.contains('e') && !str.contains('E')) return value;

    final RegExp regex = RegExp(r'(\d(?:\.(\d*))?)[eE]([+-]?\d+)');
    final match = regex.firstMatch(str);
    if (match == null) return value;

    final mantissaDecimals = match.group(2) ?? '';
    final exponent = int.parse(match.group(3)!);

    // 与 JS 逻辑对齐：toFixed(max(0, mantissa小数位数 - exponent))
    final precision = (mantissaDecimals.length - exponent).clamp(0, 20);
    final fixedStr = value.toStringAsFixed(precision);
    return double.tryParse(fixedStr) ?? value;
  }

  // =================== 四则运算 ===================

  /// 精确加法
  ///
  /// ```dart
  /// MathUtils.add(0.1, 0.2)   // 0.3（原生: 0.30000000000000004）
  /// MathUtils.add(1.23, 4.56) // 5.79
  /// ```
  static double add(num a, num b) {
    final precision = _maxInt(getPrecision(a), getPrecision(b));
    final multiplier = _pow10(precision);
    final result =
        ((a * multiplier).round() + (b * multiplier).round()) / multiplier;
    return transferToNumber(result).toDouble();
  }

  /// 精确减法
  ///
  /// ```dart
  /// MathUtils.subtract(1.0, 0.9)  // 0.1（原生: 0.09999999999999998）
  /// ```
  static double subtract(num a, num b) {
    return add(a, -b);
  }

  /// 精确乘法
  ///
  /// ```dart
  /// MathUtils.multiply(10.03, 3445.67) // 34560.1001（原生: 34560.09999999998）
  /// MathUtils.multiply(0.1, 0.2)       // 0.02（原生: 0.020000000000000004）
  /// ```
  static double multiply(num a, num b) {
    final precisionA = getPrecision(a);
    final precisionB = getPrecision(b);
    final precision = precisionA + precisionB;
    final multiplier = _pow10(precision);
    final multA = _pow10(precisionA);
    final multB = _pow10(precisionB);
    final result =
        ((a * multA).round() * (b * multB).round()) / multiplier;
    return transferToNumber(result).toDouble();
  }

  /// 别名，与 [multiply] 等价（对齐 boss 项目命名）
  static double mul(num a, num b) => multiply(a, b);

  /// 精确除法
  ///
  /// ```dart
  /// MathUtils.divide(1.0, 3.0)  // 0.3333333333333333
  /// MathUtils.divide(10.0, 0.1) // 100.0（原生: 99.99999999999999）
  /// ```
  ///
  /// [b] 为 0 时返回 0。
  static double divide(num a, num b) {
    if (b == 0) return 0;
    final precisionA = getPrecision(a);
    final precisionB = getPrecision(b);
    final step = _pow10(_maxInt(precisionA, precisionB));
    final result = (a * step) / (b * step);
    return transferToNumber(result).toDouble();
  }

  // =================== 汇总运算 ===================

  /// 精确求和（对列表中所有数值累加）
  ///
  /// ```dart
  /// MathUtils.sum([0.1, 0.2, 0.3]) // 0.6
  /// ```
  static double sum(Iterable<num> values) {
    double result = 0;
    for (final v in values) {
      result = add(result, v);
    }
    return result;
  }

  /// 四舍五入到指定小数位（业务金额场景默认 2 位）
  ///
  /// ```dart
  /// MathUtils.roundTo(34560.1001, 2)  // 34560.1
  /// MathUtils.roundTo(34560.09999999998, 2) // 34560.1
  /// ```
  static double roundTo(num value, [int decimals = 2]) {
    final multiplier = _pow10(decimals);
    return (value * multiplier).roundToDouble() / multiplier;
  }

  // =================== 私有辅助 ===================

  static int _maxInt(int a, int b) => a > b ? a : b;

  /// 10 的 [n] 次方（整数结果）
  static int _pow10(int n) {
    if (n <= 0) return 1;
    int result = 1;
    for (int i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }
}
