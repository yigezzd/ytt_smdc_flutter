/// 桌台类型表（对齐 TableType.kt）
class TableTypeEntity {
  int id;
  String code;
  String createid;
  String createname;
  String createtime;
  double excesstime;
  int isort;
  double lowamt;
  int lowtype;
  int minsalesamtflag;
  String name;
  String operid;
  String opername;
  int reservationflag;
  double serviceamt;
  int servicetype;
  int sid;
  int spid;
  int status;
  int stopflag;
  String tabletypeid;
  int trueflag;
  String updatetime;
  double starthour; // 起步小时
  double startamt; // 起步金额
  double overhour; // 超过小时
  double overamt; // 超过金额
  String begintime; // 加收开始时间
  String endtime; // 加收结束时间
  double addhour; // 加收小时
  double addamt; // 加收金额
  double maxhour; // 封顶时长
  double maxamt; // 封顶金额
  String remark;
  int starthourtype; // 起步时间类型 1小时 2分钟
  int overhourtype; // 超过时间类型 1小时 2分钟
  int addhourtype; // 加收时间类型 1小时 2分钟
  int maxhourtype; // 封顶时间类型 1小时 2分钟
  int exceedtype; // 1按一个计费时长计 2按半价计 3按实际时长计 4不计
  double freemin; // 前多少分钟不收取费用
  double exceedmin1; // 超过多少分钟1
  double exceedmin2; // 超过多少分钟2
  double calculatemin1; // 按照多少分钟1
  double calculatemin2; // 按照多少分钟2
  int automaticflag; // 1自动 0手动 服务费开始方式
  int serviceamtflag; // 按消费金额时 1折前 0折扣 计算

  TableTypeEntity({
    this.id = 0, this.code = '', this.createid = '', this.createname = '',
    this.createtime = '', this.excesstime = 0, this.isort = 0,
    this.lowamt = 0.0, this.lowtype = 0, this.minsalesamtflag = 0,
    this.name = '', this.operid = '', this.opername = '',
    this.reservationflag = 0, this.serviceamt = 0.0, this.servicetype = 0,
    this.sid = 0, this.spid = 0, this.status = 0, this.stopflag = 0,
    this.tabletypeid = '', this.trueflag = 0, this.updatetime = '',
    this.starthour = 0.0, this.startamt = 0.0,
    this.overhour = 0.0, this.overamt = 0.0,
    this.begintime = '', this.endtime = '',
    this.addhour = 0.0, this.addamt = 0.0,
    this.maxhour = 0.0, this.maxamt = 0.0, this.remark = '',
    this.starthourtype = 0, this.overhourtype = 0,
    this.addhourtype = 0, this.maxhourtype = 0, this.exceedtype = 0,
    this.freemin = 0.0, this.exceedmin1 = 0.0, this.exceedmin2 = 0.0,
    this.calculatemin1 = 0.0, this.calculatemin2 = 0.0,
    this.automaticflag = 1, this.serviceamtflag = 1,
  });

  factory TableTypeEntity.fromMap(Map<String, dynamic> m) => TableTypeEntity(
        id: m['id'] as int? ?? 0,
        code: m['code']?.toString() ?? '',
        createid: m['createid']?.toString() ?? '',
        createname: m['createname']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        excesstime: (m['excesstime'] as num?)?.toDouble() ?? 0,
        isort: m['isort'] as int? ?? 0,
        lowamt: (m['lowamt'] as num?)?.toDouble() ?? 0.0,
        lowtype: m['lowtype'] as int? ?? 0,
        minsalesamtflag: m['minsalesamtflag'] as int? ?? 0,
        name: m['name']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        reservationflag: m['reservationflag'] as int? ?? 0,
        serviceamt: (m['serviceamt'] as num?)?.toDouble() ?? 0.0,
        servicetype: m['servicetype'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        tabletypeid: m['tabletypeid']?.toString() ?? '',
        trueflag: m['trueflag'] as int? ?? 0,
        updatetime: m['updatetime']?.toString() ?? '',
        starthour: (m['starthour'] as num?)?.toDouble() ?? 0.0,
        startamt: (m['startamt'] as num?)?.toDouble() ?? 0.0,
        overhour: (m['overhour'] as num?)?.toDouble() ?? 0.0,
        overamt: (m['overamt'] as num?)?.toDouble() ?? 0.0,
        begintime: m['begintime']?.toString() ?? '',
        endtime: m['endtime']?.toString() ?? '',
        addhour: (m['addhour'] as num?)?.toDouble() ?? 0.0,
        addamt: (m['addamt'] as num?)?.toDouble() ?? 0.0,
        maxhour: (m['maxhour'] as num?)?.toDouble() ?? 0.0,
        maxamt: (m['maxamt'] as num?)?.toDouble() ?? 0.0,
        remark: m['remark']?.toString() ?? '',
        starthourtype: m['starthourtype'] as int? ?? 0,
        overhourtype: m['overhourtype'] as int? ?? 0,
        addhourtype: m['addhourtype'] as int? ?? 0,
        maxhourtype: m['maxhourtype'] as int? ?? 0,
        exceedtype: m['exceedtype'] as int? ?? 0,
        freemin: (m['freemin'] as num?)?.toDouble() ?? 0.0,
        exceedmin1: (m['exceedmin1'] as num?)?.toDouble() ?? 0.0,
        exceedmin2: (m['exceedmin2'] as num?)?.toDouble() ?? 0.0,
        calculatemin1: (m['calculatemin1'] as num?)?.toDouble() ?? 0.0,
        calculatemin2: (m['calculatemin2'] as num?)?.toDouble() ?? 0.0,
        automaticflag: m['automaticflag'] as int? ?? 1,
        serviceamtflag: m['serviceamtflag'] as int? ?? 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'code': code, 'createid': createid, 'createname': createname,
        'createtime': createtime, 'excesstime': excesstime, 'isort': isort,
        'lowamt': lowamt, 'lowtype': lowtype, 'minsalesamtflag': minsalesamtflag,
        'name': name, 'operid': operid, 'opername': opername,
        'reservationflag': reservationflag, 'serviceamt': serviceamt,
        'servicetype': servicetype, 'sid': sid, 'spid': spid,
        'status': status, 'stopflag': stopflag, 'tabletypeid': tabletypeid,
        'trueflag': trueflag, 'updatetime': updatetime,
        'starthour': starthour, 'startamt': startamt,
        'overhour': overhour, 'overamt': overamt,
        'begintime': begintime, 'endtime': endtime,
        'addhour': addhour, 'addamt': addamt,
        'maxhour': maxhour, 'maxamt': maxamt, 'remark': remark,
        'starthourtype': starthourtype, 'overhourtype': overhourtype,
        'addhourtype': addhourtype, 'maxhourtype': maxhourtype,
        'exceedtype': exceedtype, 'freemin': freemin,
        'exceedmin1': exceedmin1, 'exceedmin2': exceedmin2,
        'calculatemin1': calculatemin1, 'calculatemin2': calculatemin2,
        'automaticflag': automaticflag, 'serviceamtflag': serviceamtflag,
      };
}
