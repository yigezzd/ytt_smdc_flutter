/// 桌台区域表（对齐 AbleArea.java）
class AbleAreaEntity {
  int id;
  int spid; // 总部id
  int sid; // 门店id
  int status; // 状态1正常 0删除
  int stopflag; // 0启用 1停用
  int isort; // 序号
  String areaid; // 区域id
  String name; // 区域名称
  String createtime;
  String createid;
  String createname;
  String updatetime;
  String operid;
  String opername;
  String isalltype; // 是否全选菜品分类（1=全选，0=部分选择）

  AbleAreaEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.status = 0, this.stopflag = 0, this.isort = 0,
    this.areaid = '', this.name = '',
    this.createtime = '', this.createid = '', this.createname = '',
    this.updatetime = '', this.operid = '', this.opername = '',
    this.isalltype = '',
  });

  factory AbleAreaEntity.fromMap(Map<String, dynamic> m) => AbleAreaEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        isort: m['isort'] as int? ?? 0,
        areaid: m['areaid']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        createid: m['createid']?.toString() ?? '',
        createname: m['createname']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
        isalltype: m['isalltype']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'status': status, 'stopflag': stopflag, 'isort': isort,
        'areaid': areaid, 'name': name,
        'createtime': createtime, 'createid': createid, 'createname': createname,
        'updatetime': updatetime, 'operid': operid, 'opername': opername,
        'isalltype': isalltype,
      };
}
