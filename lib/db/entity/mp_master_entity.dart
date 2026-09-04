import 'mp_product_or_type_entity.dart';
import 'mp_rule_entity.dart';

/// 促销主表（对齐 MPMaster.kt，含 @Ignore 字段）
class MPMasterEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  int status;
  int dateflag; // 0长期有效 1指定日期
  String billid;
  String billno;
  String name;
  String createtime;
  String updatetime;
  String operid;
  String opername;
  String startdate;
  String enddate;
  int billtype; // 1.分类折扣 2.菜品折扣 3.特价菜 4.买赠 5.满量折扣 6.满减 7.满赠 8.满折
  String effectday; // 活动星期1111111
  int posflag;
  int scanflag;
  int takeoutflag;
  int applytype; // 适用菜品：0不限制 1部分分类 2部分菜品
  int stopflag;
  int appflag;
  int number; // 执行次数
  int billnum; // 订单量
  int vipflag; // 1不限，2散客，3会员类型
  double payment;
  double discountamt;
  String createid;
  String createname;
  String updateid;
  int startdateLong;
  int enddateLong;
  String updatename;
  int nDiscountform; // 第N份优惠-优惠形式:1=折扣;2=特价;3=减价
  double nSellnum; // 第N份优惠-购买第几份
  double nDis; // 第N份优惠-折扣率/特价/减价
  int nCondition; // 1=购买相同商品 2=购买不同商品
  int nRule; // 1价格降序分组优惠较低 2价格降序排序从最低开始
  int billmaxnum; // 最大享受次数

  // ── @Ignore 字段（不入库） ──
  List<MpProductOrTypeEntity>? mpProOrType;
  List<MpRuleEntity>? mpPtRules;

  MPMasterEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.status = 0, this.dateflag = 0,
    this.billid = '', this.billno = '', this.name = '',
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
    this.startdate = '', this.enddate = '',
    this.billtype = -1, this.effectday = '',
    this.posflag = -1, this.scanflag = -1, this.takeoutflag = -1,
    this.applytype = -1, this.stopflag = -1, this.appflag = -1,
    this.number = -1, this.billnum = -1,
    this.vipflag = 1, this.payment = 0.0, this.discountamt = 0.0,
    this.createid = '', this.createname = '',
    this.updateid = '', this.startdateLong = 0, this.enddateLong = 0,
    this.updatename = '',
    this.nDiscountform = 0, this.nSellnum = 0.0, this.nDis = 0.0,
    this.nCondition = 0, this.nRule = 0, this.billmaxnum = 0,
    this.mpProOrType, this.mpPtRules,
  });

  factory MPMasterEntity.fromMap(Map<String, dynamic> m) => MPMasterEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        dateflag: m['dateflag'] as int? ?? 0,
        billid: m['billid']?.toString() ?? '',
        billno: m['billno']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        startdate: m['startdate']?.toString() ?? '',
        enddate: m['enddate']?.toString() ?? '',
        billtype: m['billtype'] as int? ?? -1,
        effectday: m['effectday']?.toString() ?? '',
        posflag: m['posflag'] as int? ?? -1,
        scanflag: m['scanflag'] as int? ?? -1,
        takeoutflag: m['takeoutflag'] as int? ?? -1,
        applytype: m['applytype'] as int? ?? -1,
        stopflag: m['stopflag'] as int? ?? -1,
        appflag: m['appflag'] as int? ?? -1,
        number: m['number'] as int? ?? -1,
        billnum: m['billnum'] as int? ?? -1,
        vipflag: m['vipflag'] as int? ?? 1,
        payment: (m['payment'] as num?)?.toDouble() ?? 0.0,
        discountamt: (m['discountamt'] as num?)?.toDouble() ?? 0.0,
        createid: m['createid']?.toString() ?? '',
        createname: m['createname']?.toString() ?? '',
        updateid: m['updateid']?.toString() ?? '',
        startdateLong: m['startdateLong'] as int? ?? 0,
        enddateLong: m['enddateLong'] as int? ?? 0,
        updatename: m['updatename']?.toString() ?? '',
        nDiscountform: m['n_discountform'] as int? ?? 0,
        nSellnum: (m['n_sellnum'] as num?)?.toDouble() ?? 0.0,
        nDis: (m['n_dis'] as num?)?.toDouble() ?? 0.0,
        nCondition: m['n_condition'] as int? ?? 0,
        nRule: m['n_rule'] as int? ?? 0,
        billmaxnum: m['billmaxnum'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'status': status, 'dateflag': dateflag,
        'billid': billid, 'billno': billno, 'name': name,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
        'startdate': startdate, 'enddate': enddate,
        'billtype': billtype, 'effectday': effectday,
        'posflag': posflag, 'scanflag': scanflag, 'takeoutflag': takeoutflag,
        'applytype': applytype, 'stopflag': stopflag, 'appflag': appflag,
        'number': number, 'billnum': billnum,
        'vipflag': vipflag, 'payment': payment, 'discountamt': discountamt,
        'createid': createid, 'createname': createname,
        'updateid': updateid, 'startdateLong': startdateLong,
        'enddateLong': enddateLong, 'updatename': updatename,
        'n_discountform': nDiscountform, 'n_sellnum': nSellnum,
        'n_dis': nDis, 'n_condition': nCondition,
        'n_rule': nRule, 'billmaxnum': billmaxnum,
      };
}
