/// 商品售卖日期表（对齐 ProductDate.kt）
class ProductDateEntity {
  int id;
  int spid;
  int sid;
  int status;
  int isort;
  int stopflag; // 0启用 1停用
  int cycletype; // 售卖周期：1每天；2每周；3每月
  int datetype; // 售卖日期类型：1不限；2指定时间
  String productid;
  String begindate;
  String enddate;
  String saleweek; // 每周几售卖，按位与判断：1111111
  String salemonth; // 每月几号售卖，逗号分隔：9,15,19
  String saletime; // 售卖时段：10:00-16:30|17:30-18:29
  String createtime;
  String updatetime;
  String operid;
  String opername;
  int timetype; // 售卖时段标识 1不限 2指定时段

  ProductDateEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.status = 0, this.isort = 0, this.stopflag = 0,
    this.cycletype = 0, this.datetype = 0,
    this.productid = '', this.begindate = '', this.enddate = '',
    this.saleweek = '', this.salemonth = '', this.saletime = '',
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '', this.timetype = 0,
  });

  factory ProductDateEntity.fromMap(Map<String, dynamic> m) => ProductDateEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        isort: m['isort'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        cycletype: m['cycletype'] as int? ?? 0,
        datetype: m['datetype'] as int? ?? 0,
        productid: m['productid']?.toString() ?? '',
        begindate: m['begindate']?.toString() ?? '',
        enddate: m['enddate']?.toString() ?? '',
        saleweek: m['saleweek']?.toString() ?? '',
        salemonth: m['salemonth']?.toString() ?? '',
        saletime: m['saletime']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        timetype: m['timetype'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'status': status, 'isort': isort, 'stopflag': stopflag,
        'cycletype': cycletype, 'datetype': datetype,
        'productid': productid, 'begindate': begindate, 'enddate': enddate,
        'saleweek': saleweek, 'salemonth': salemonth, 'saletime': saletime,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername, 'timetype': timetype,
      };
}
