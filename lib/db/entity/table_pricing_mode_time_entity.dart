/// 附加费区间表（对齐 TablePricingModeTime.kt，含 @Ignore 字段）
class TablePricingModeTimeEntity {
  // ── 持久化字段 ──
  int id;
  int sid;
  int spid;
  int status; // 1正常
  String tabletypeid;
  String starttime;
  String endtime;
  int min; // 时长分钟
  double price; // 非周末价
  double weekprice; // 周末价
  int isort;
  String createtime;
  String updatetime;

  // ── @Ignore 字段（不入库） ──
  bool isCheck;
  DateTime? checkDay;
  DateTime? checkTime;
  int usedMinues;

  TablePricingModeTimeEntity({
    this.id = 0, this.sid = 0, this.spid = 0, this.status = 0,
    this.tabletypeid = '', this.starttime = '', this.endtime = '',
    this.min = 0, this.price = 0.0, this.weekprice = 0.0,
    this.isort = 0, this.createtime = '', this.updatetime = '',
    this.isCheck = false, this.checkDay, this.checkTime, this.usedMinues = 0,
  });

  factory TablePricingModeTimeEntity.fromMap(Map<String, dynamic> m) =>
      TablePricingModeTimeEntity(
        id: m['id'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        tabletypeid: m['tabletypeid']?.toString() ?? '',
        starttime: m['starttime']?.toString() ?? '',
        endtime: m['endtime']?.toString() ?? '',
        min: m['min'] as int? ?? 0,
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
        weekprice: (m['weekprice'] as num?)?.toDouble() ?? 0.0,
        isort: m['isort'] as int? ?? 0,
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'sid': sid, 'spid': spid, 'status': status,
        'tabletypeid': tabletypeid, 'starttime': starttime, 'endtime': endtime,
        'min': min, 'price': price, 'weekprice': weekprice,
        'isort': isort, 'createtime': createtime, 'updatetime': updatetime,
      };
}
