import 'entity_map_utils.dart';
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
        id: readMapInt(m['id']),
        spid: readMapInt(m['spid']),
        sid: readMapInt(m['sid']),
        status: readMapInt(m['status']),
        dateflag: readMapInt(m['dateflag']),
        billid: m['billid']?.toString() ?? '',
        billno: m['billno']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        startdate: m['startdate']?.toString() ?? '',
        enddate: m['enddate']?.toString() ?? '',
        billtype: readMapInt(m['billtype'], -1),
        effectday: m['effectday']?.toString() ?? '',
        posflag: readMapInt(m['posflag'], -1),
        scanflag: readMapInt(m['scanflag'], -1),
        takeoutflag: readMapInt(m['takeoutflag'], -1),
        applytype: readMapInt(m['applytype'], -1),
        stopflag: readMapInt(m['stopflag'], -1),
        appflag: readMapInt(m['appflag'], -1),
        number: readMapInt(m['number'], -1),
        billnum: readMapInt(m['billnum'], -1),
        vipflag: readMapInt(m['vipflag'], 1),
        payment: readMapDouble(m['payment']),
        discountamt: readMapDouble(m['discountamt']),
        createid: m['createid']?.toString() ?? '',
        createname: m['createname']?.toString() ?? '',
        updateid: m['updateid']?.toString() ?? '',
        startdateLong: readMapInt(m['startdateLong']),
        enddateLong: readMapInt(m['enddateLong']),
        updatename: m['updatename']?.toString() ?? '',
        nDiscountform: readMapInt(m['n_discountform']),
        nSellnum: readMapDouble(m['n_sellnum']),
        nDis: readMapDouble(m['n_dis']),
        nCondition: readMapInt(m['n_condition']),
        nRule: readMapInt(m['n_rule']),
        billmaxnum: readMapInt(m['billmaxnum']),
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
