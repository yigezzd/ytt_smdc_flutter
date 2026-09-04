/// 必点菜主表（对齐 MustMaster.kt）
class MustMasterEntity {
  int id;
  int spid;
  int sid;
  int stopflag;
  int posflag1;
  int posflag;
  int scanflag2;
  int scanflag1;
  int scanflag;
  int takeoutflag;
  int outcheckflag;
  int mustrule;
  int musttype;
  int appflag;
  int appflag1;
  int dateflag;
  int checkflag;
  int status;
  String startdate;
  String billid;
  String createid;
  String createname;
  String tableareas; // 区域名称
  String createtime;
  String enddate;
  String updateid;
  String name;
  String productnames;
  String updatetime;
  String updatename;
  String billno;
  String areaid;
  String? timeperiod1;
  String? timeperiod2;
  String? timeperiod3;

  MustMasterEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.stopflag = 0, this.posflag1 = 0, this.posflag = 0,
    this.scanflag2 = 0, this.scanflag1 = 0, this.scanflag = 0,
    this.takeoutflag = 0, this.outcheckflag = 0,
    this.mustrule = 0, this.musttype = 0,
    this.appflag = 0, this.appflag1 = 0,
    this.dateflag = 0, this.checkflag = 0, this.status = 0,
    this.startdate = '', this.billid = '',
    this.createid = '', this.createname = '', this.tableareas = '',
    this.createtime = '', this.enddate = '',
    this.updateid = '', this.name = '', this.productnames = '',
    this.updatetime = '', this.updatename = '',
    this.billno = '', this.areaid = '',
    this.timeperiod1, this.timeperiod2, this.timeperiod3,
  });

  factory MustMasterEntity.fromMap(Map<String, dynamic> m) => MustMasterEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        posflag1: m['posflag1'] as int? ?? 0,
        posflag: m['posflag'] as int? ?? 0,
        scanflag2: m['scanflag2'] as int? ?? 0,
        scanflag1: m['scanflag1'] as int? ?? 0,
        scanflag: m['scanflag'] as int? ?? 0,
        takeoutflag: m['takeoutflag'] as int? ?? 0,
        outcheckflag: m['outcheckflag'] as int? ?? 0,
        mustrule: m['mustrule'] as int? ?? 0,
        musttype: m['musttype'] as int? ?? 0,
        appflag: m['appflag'] as int? ?? 0,
        appflag1: m['appflag1'] as int? ?? 0,
        dateflag: m['dateflag'] as int? ?? 0,
        checkflag: m['checkflag'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        startdate: m['startdate']?.toString() ?? '',
        billid: m['billid']?.toString() ?? '',
        createid: m['createid']?.toString() ?? '',
        createname: m['createname']?.toString() ?? '',
        tableareas: m['tableareas']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        enddate: m['enddate']?.toString() ?? '',
        updateid: m['updateid']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        productnames: m['productnames']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        updatename: m['updatename']?.toString() ?? '',
        billno: m['billno']?.toString() ?? '',
        areaid: m['areaid']?.toString() ?? '',
        timeperiod1: m['timeperiod1']?.toString(),
        timeperiod2: m['timeperiod2']?.toString(),
        timeperiod3: m['timeperiod3']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'stopflag': stopflag, 'posflag1': posflag1, 'posflag': posflag,
        'scanflag2': scanflag2, 'scanflag1': scanflag1, 'scanflag': scanflag,
        'takeoutflag': takeoutflag, 'outcheckflag': outcheckflag,
        'mustrule': mustrule, 'musttype': musttype,
        'appflag': appflag, 'appflag1': appflag1,
        'dateflag': dateflag, 'checkflag': checkflag, 'status': status,
        'startdate': startdate, 'billid': billid,
        'createid': createid, 'createname': createname,
        'tableareas': tableareas, 'createtime': createtime,
        'enddate': enddate, 'updateid': updateid,
        'name': name, 'productnames': productnames,
        'updatetime': updatetime, 'updatename': updatename,
        'billno': billno, 'areaid': areaid,
        'timeperiod1': timeperiod1, 'timeperiod2': timeperiod2, 'timeperiod3': timeperiod3,
      };
}
