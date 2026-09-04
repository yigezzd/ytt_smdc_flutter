/// 商品规格表（对齐 SpecInfo.kt）
class SpecInfoEntity {
  int id;
  int spid;
  int sid;
  int isort;
  int stopflag; // 0正常 1停用
  int status; // 1正常 0删除
  String specid;
  String name;
  String createtime;
  String updatetime;
  String operid;
  String opername;

  SpecInfoEntity({
    this.id = 0,
    this.spid = 0,
    this.sid = 0,
    this.isort = 0,
    this.stopflag = 0,
    this.status = 0,
    this.specid = '',
    this.name = '',
    this.createtime = '',
    this.updatetime = '',
    this.operid = '',
    this.opername = '',
  });

  factory SpecInfoEntity.fromMap(Map<String, dynamic> m) => SpecInfoEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        isort: m['isort'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        specid: m['specid']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid, 'isort': isort,
        'stopflag': stopflag, 'status': status,
        'specid': specid, 'name': name,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
      };
}
