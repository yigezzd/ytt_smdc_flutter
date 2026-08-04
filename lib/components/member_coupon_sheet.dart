import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/util/toast_utils.dart';

/// 品牌红
const Color _kBrandRed = Color(0xFFE13426);

/// 会员优惠券模型（对齐 smdcapp VipCouponBean）
class MemberCoupon {
  MemberCoupon({
    required this.favid,
    required this.favname,
    this.favamt = 0,
    this.favtype = 0,
    this.enddate = '',
  });

  factory MemberCoupon.fromJson(Map<String, dynamic> json) {
    return MemberCoupon(
      favid: json['favid']?.toString() ?? json['id']?.toString() ?? '',
      favname: json['favname']?.toString() ?? json['name']?.toString() ?? '优惠券',
      favamt: _toDouble(json['favamt'] ?? json['amount']),
      favtype: _toInt(json['favtype']),
      enddate: json['enddate']?.toString() ?? '',
    );
  }

  final String favid;
  final String favname;

  /// 优惠金额/折扣值
  final double favamt;

  /// 券类型（1代金券 2折扣券 3礼品券）
  final int favtype;
  final String enddate;

  String get typeText {
    switch (favtype) {
      case 1:
        return '代金券';
      case 2:
        return '折扣券';
      case 3:
        return '礼品券';
      default:
        return '优惠券';
    }
  }

  String get amountText => favtype == 2 ? '${favamt}折' : '¥$favamt';
}

/// 会员优惠券选择弹窗（对齐 smdcapp CouponListActivity + MemberDateilsActivity）
///
/// 展示会员可用优惠券列表，选择后用于结算抵扣。
class MemberCouponSheet extends StatefulWidget {
  const MemberCouponSheet({
    super.key,
    required this.vipid,
    this.master = '',
    this.projectlist = '',
  });

  final String vipid;
  final String master;
  final String projectlist;

  /// 显示优惠券选择弹窗，返回选中的优惠券或 null
  static Future<MemberCoupon?> show(
    BuildContext context, {
    required String vipid,
    String master = '',
    String projectlist = '',
  }) {
    return showModalBottomSheet<MemberCoupon>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MemberCouponSheet(
        vipid: vipid,
        master: master,
        projectlist: projectlist,
      ),
    );
  }

  @override
  State<MemberCouponSheet> createState() => _MemberCouponSheetState();
}

class _MemberCouponSheetState extends State<MemberCouponSheet> {
  List<MemberCoupon> _coupons = <MemberCoupon>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  /// 加载会员优惠券（对齐 smdcapp searchVipFavList）
  Future<void> _loadCoupons() async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.searchVipFavList,
        <String, dynamic>{
          'vipid': widget.vipid,
          'master': widget.master,
          'projectlist': widget.projectlist,
          'clienttype': 'APP',
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
      if (data is Map<String, dynamic>) {
        final dynamic l = data['list'] ?? data['favlist'];
        if (l is List) {
          list = l.whereType<Map<String, dynamic>>().toList();
        }
      } else if (data is List) {
        list = data.whereType<Map<String, dynamic>>().toList();
      }
      _coupons = list.map(MemberCoupon.fromJson).toList();
    } catch (_) {
      _coupons = <MemberCoupon>[];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 10),
          Center(
            child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E6EB), borderRadius: BorderRadius.circular(2))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: <Widget>[
                const Expanded(child: Text('会员优惠券', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20, color: Color(0xFFC9CDD4))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _coupons.isEmpty
                    ? const Center(child: Text('暂无可用优惠券', style: TextStyle(color: Color(0xFF999999))))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _coupons.length,
                        itemBuilder: (BuildContext ctx, int i) => _buildCouponCard(_coupons[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponCard(MemberCoupon coupon) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, coupon),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFBDDD9)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: _kBrandRed, borderRadius: BorderRadius.circular(6)),
              child: Text(
                coupon.amountText,
                style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(coupon.favname, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    '${coupon.typeText}  ${coupon.enddate.isNotEmpty ? '有效期至 ${coupon.enddate}' : ''}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF999999)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFC9CDD4)),
          ],
        ),
      ),
    );
  }
}

/// 会员优惠券核销辅助（对齐 smdcapp voucherVerify）
class CouponVerifyHelper {
  CouponVerifyHelper._();

  /// 核销优惠券（券号核销）
  static Future<bool> verify({
    required String master,
    required String projectlist,
    required String fav,
  }) async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.voucherVerify,
        <String, dynamic>{
          'master': master,
          'projectlist': projectlist,
          'clienttype': 'APP',
          'fav': fav,
        },
      );
      final bool success = resp.containsKey('Success')
          ? resp['Success'] == true
          : (resp['retcode'] == 0);
      return success;
    } catch (_) {
      return false;
    }
  }
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}
