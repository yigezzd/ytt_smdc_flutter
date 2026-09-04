/// 做法分组表（对齐 CookGroup.kt）
class CookGroupEntity {
  int id;
  int spid;
  int sid;
  int status;
  int editqtyflag; // 0不可修改做法数量 1可
  String groupid;
  String name;
  String createtime;
  String updatetime;
  String operid;
  String opername;
  int? gisort; // 做法分组排序

  CookGroupEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.status = 0, this.editqtyflag = 0,
    this.groupid = '', this.name = '',
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
    this.gisort = 0,
  });

  factory CookGroupEntity.fromMap(Map<String, dynamic> m) => CookGroupEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        editqtyflag: m['editqtyflag'] as int? ?? 0,
        groupid: m['groupid']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        gisort: m['gisort'] as int?,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'status': status, 'editqtyflag': editqtyflag,
        'groupid': groupid, 'name': name,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername, 'gisort': gisort,
      };
}
