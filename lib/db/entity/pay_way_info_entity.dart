/// 支付方式表（对齐 PayWayInfo.kt，含 @Ignore 字段）
class PayWayInfoEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  int fuseflag;
  int handoverflag;
  int opencashflag;
  int padflag;
  int stopflag;
  double rate;
  int pointflag;
  int operflag;
  int isort;
  int paytype;
  int scanflag;
  int status;
  String value;
  String createtime;
  String code;
  String operid;
  String remark;
  String opername;
  String name;
  String updatetime;
  String payid;
  String faceflag;
  String actulamt; // 实付金额
  String virtualamt; // 虚付金额
  String faceamt; // 面额

  // ── @Ignore 字段（不入库） ──
  bool isSelect;
  String depositflag;

  PayWayInfoEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.fuseflag = 0, this.handoverflag = 0, this.opencashflag = 0,
    this.padflag = 0, this.stopflag = 0, this.rate = 0.0,
    this.pointflag = 0, this.operflag = 0, this.isort = 0,
    this.paytype = 0, this.scanflag = 0, this.status = 0,
    this.value = '', this.createtime = '', this.code = '',
    this.operid = '', this.remark = '', this.opername = '',
    this.name = '', this.updatetime = '', this.payid = '',
    this.faceflag = '', this.actulamt = '', this.virtualamt = '', this.faceamt = '',
    this.isSelect = false, this.depositflag = '',
  });

  factory PayWayInfoEntity.fromMap(Map<String, dynamic> m) => PayWayInfoEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        fuseflag: m['fuseflag'] as int? ?? 0,
        handoverflag: m['handoverflag'] as int? ?? 0,
        opencashflag: m['opencashflag'] as int? ?? 0,
        padflag: m['padflag'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        rate: (m['rate'] as num?)?.toDouble() ?? 0.0,
        pointflag: m['pointflag'] as int? ?? 0,
        operflag: m['operflag'] as int? ?? 0,
        isort: m['isort'] as int? ?? 0,
        paytype: m['paytype'] as int? ?? 0,
        scanflag: m['scanflag'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        value: m['value']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        remark: m['remark']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        payid: m['payid']?.toString() ?? '',
        faceflag: m['faceflag']?.toString() ?? '',
        actulamt: m['actulamt']?.toString() ?? '',
        virtualamt: m['virtualamt']?.toString() ?? '',
        faceamt: m['faceamt']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'fuseflag': fuseflag, 'handoverflag': handoverflag,
        'opencashflag': opencashflag, 'padflag': padflag,
        'stopflag': stopflag, 'rate': rate,
        'pointflag': pointflag, 'operflag': operflag,
        'isort': isort, 'paytype': paytype, 'scanflag': scanflag, 'status': status,
        'value': value, 'createtime': createtime, 'code': code,
        'operid': operid, 'remark': remark, 'opername': opername,
        'name': name, 'updatetime': updatetime, 'payid': payid,
        'faceflag': faceflag, 'actulamt': actulamt,
        'virtualamt': virtualamt, 'faceamt': faceamt,
      };
}
