/// 促销规则表（对齐 MPRule.kt）
class MpRuleEntity {
  int id;
  int spid;
  int sid;
  double discount; // 折扣
  double qty; // 要满足的份数
  double giveqty; // 赠送的份数
  double reduceamt; // 减少金额
  double amt; // 满足金额（满减/满赠/满折要用到）
  String billid;
  String ruleid; // 规则唯一标识
  String productid;
  String typeid;
  String specid; // 规格唯一标识
  String saletype; // 1需要这些商品或分类来满足规则 2赠送的

  MpRuleEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.discount = 0.0, this.qty = 0.0, this.giveqty = 0.0,
    this.reduceamt = 0.0, this.amt = 0.0,
    this.billid = '', this.ruleid = '',
    this.productid = '', this.typeid = '',
    this.specid = '', this.saletype = '',
  });

  factory MpRuleEntity.fromMap(Map<String, dynamic> m) => MpRuleEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        discount: (m['discount'] as num?)?.toDouble() ?? 0.0,
        qty: (m['qty'] as num?)?.toDouble() ?? 0.0,
        giveqty: (m['giveqty'] as num?)?.toDouble() ?? 0.0,
        reduceamt: (m['reduceamt'] as num?)?.toDouble() ?? 0.0,
        amt: (m['amt'] as num?)?.toDouble() ?? 0.0,
        billid: m['billid']?.toString() ?? '',
        ruleid: m['ruleid']?.toString() ?? '',
        productid: m['productid']?.toString() ?? '',
        typeid: m['typeid']?.toString() ?? '',
        specid: m['specid']?.toString() ?? '',
        saletype: m['saletype']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'discount': discount, 'qty': qty, 'giveqty': giveqty,
        'reduceamt': reduceamt, 'amt': amt,
        'billid': billid, 'ruleid': ruleid,
        'productid': productid, 'typeid': typeid,
        'specid': specid, 'saletype': saletype,
      };
}
