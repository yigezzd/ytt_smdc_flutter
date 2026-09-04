/// 吃法分组表（对齐 EatGroup.kt）
class EatGroupEntity {
  int id;
  int spid;
  int sid;
  String groupid;
  String name;
  int status; // 1正常 0删除
  int gisort; // 分组排序号
  String createtime;
  String updatetime;
  String operid;
  String opername;

  EatGroupEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.groupid = '', this.name = '',
    this.status = 1, this.gisort = 0,
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
  });

  factory EatGroupEntity.fromMap(Map<String, dynamic> m) => EatGroupEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        groupid: m['groupid']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        status: m['status'] as int? ?? 1,
        gisort: m['gisort'] as int? ?? 0,
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'groupid': groupid, 'name': name,
        'status': status, 'gisort': gisort,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
      };
}
