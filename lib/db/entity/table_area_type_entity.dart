/// 桌台绑定指定分类表（对齐 TableAreaType.kt）
class TableAreaTypeEntity {
  int id;
  String createtime;
  String createid;
  String areaid;
  String typeid;
  String typename;
  String createname;
  int level;
  int spid;

  TableAreaTypeEntity({
    this.id = 0,
    this.createtime = '', this.createid = '',
    this.areaid = '', this.typeid = '', this.typename = '',
    this.createname = '', this.level = 0, this.spid = 0,
  });

  factory TableAreaTypeEntity.fromMap(Map<String, dynamic> m) => TableAreaTypeEntity(
        id: m['id'] as int? ?? 0,
        createtime: m['createtime']?.toString() ?? '',
        createid: m['createid']?.toString() ?? '',
        areaid: m['areaid']?.toString() ?? '',
        typeid: m['typeid']?.toString() ?? '',
        typename: m['typename']?.toString() ?? '',
        createname: m['createname']?.toString() ?? '',
        level: m['level'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'createtime': createtime, 'createid': createid,
        'areaid': areaid, 'typeid': typeid, 'typename': typename,
        'createname': createname, 'level': level, 'spid': spid,
      };
}
