import 'package:flutter_deer/util/coupon_amount_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 券抵扣金额回测
///
/// 场景：订单有两道菜——小姜 ¥3.80×8（¥30.40）、哇哈哈 ¥6×4（¥24），
/// 使用一张“哇哈哈”项目券，只能核销券自身约定的份数，不能把 4 份全部抵扣。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Map<String, dynamic>> details() => <Map<String, dynamic>>[
        <String, dynamic>{
          'productname': '小姜',
          'typename': '凉菜',
          'qty': 8,
          'rramt': 30.40,
        },
        <String, dynamic>{
          'productname': '哇哈哈',
          'typename': '饮料',
          'qty': 4,
          'rramt': 24.0,
        },
      ];

  Map<String, dynamic> projectCoupon({double faceamt = 0, double qty = 0}) =>
      <String, dynamic>{
        'favtype': 2,
        'faceamt': faceamt,
        'proflag': '1',
        'pronames': '哇哈哈',
        'qty': qty,
      };

  group('项目券按券份数抵扣', () {
    test('无面额时 4 份菜品只抵扣 1 份，不是整行 24', () {
      final double amt = calcCouponDeductAmount(projectCoupon(), details());
      expect(amt, 6.0);
    });

    test('券份数为 2 时抵扣 2 份', () {
      final double amt =
          calcCouponDeductAmount(projectCoupon(qty: 2), details());
      expect(amt, 12.0);
    });

    test('有面额时以面额为上限（对齐 smdcapp）', () {
      expect(
        calcCouponDeductAmount(projectCoupon(faceamt: 6), details()),
        6.0,
      );
      expect(
        calcCouponDeductAmount(projectCoupon(faceamt: 12), details()),
        12.0,
      );
      expect(
        calcCouponDeductAmount(projectCoupon(faceamt: 24), details()),
        24.0,
      );
    });

    test('面额超过适用商品金额时按适用商品金额封顶', () {
      expect(
        calcCouponDeductAmount(projectCoupon(faceamt: 100), details()),
        24.0,
      );
    });

    test('不适用当前订单时返回 0', () {
      final Map<String, dynamic> coupon = projectCoupon()
        ..['pronames'] = '雪碧';
      expect(calcCouponDeductAmount(coupon, details()), 0.0);
    });

    test('指定商品不可用：只抵扣可用菜品的 1 份', () {
      final Map<String, dynamic> coupon = <String, dynamic>{
        'favtype': 2,
        'faceamt': 0,
        'proflag': '2',
        'pronames': '哇哈哈',
      };
      expect(calcCouponDeductAmount(coupon, details()), 3.8);
    });
  });

  group('现金券', () {
    test('按面额抵扣', () {
      final Map<String, dynamic> coupon = <String, dynamic>{
        'favtype': 1,
        'faceamt': 10,
      };
      expect(calcCouponDeductAmount(coupon, details()), 10.0);
    });

    test('面额超过订单金额时按订单金额封顶', () {
      final Map<String, dynamic> coupon = <String, dynamic>{
        'favtype': 1,
        'faceamt': 100,
      };
      expect(calcCouponDeductAmount(coupon, details()), 54.4);
    });
  });
}
