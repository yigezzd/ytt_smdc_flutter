/// 商品单位表（对齐 ProductUnit.kt）
class ProductUnitEntity {
  // ── 持久化字段 ──
  int id;
  int spid;
  int sid;
  int status;
  int isort;
  int stopflag; // 0启用 1停用
  String unitid; // 单位id（备用）
  String name; // 单位名称
  String createtime;
  String updatetime;
  String operid;
  String opername;

  // ── @Ignore 字段（不入库） ──
  bool isCheck;

  ProductUnitEntity({
    this.id = 0, this.spid = 0, this.sid = 0,
    this.status = 0, this.isort = 0, this.stopflag = 0,
    this.unitid = '', this.name = '',
    this.createtime = '', this.updatetime = '',
    this.operid = '', this.opername = '',
    this.isCheck = false,
  });

  factory ProductUnitEntity.fromMap(Map<String, dynamic> m) => ProductUnitEntity(
        id: m['id'] as int? ?? 0,
        spid: m['spid'] as int? ?? 0,
        sid: m['sid'] as int? ?? 0,
        status: m['status'] as int? ?? 0,
        isort: m['isort'] as int? ?? 0,
        stopflag: m['stopflag'] as int? ?? 0,
        unitid: m['unitid']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        createtime: m['createtime']?.toString() ?? '',
        updatetime: m['updatetime']?.toString() ?? '',
        operid: m['operid']?.toString() ?? '',
        opername: m['opername']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'spid': spid, 'sid': sid,
        'status': status, 'isort': isort, 'stopflag': stopflag,
        'unitid': unitid, 'name': name,
        'createtime': createtime, 'updatetime': updatetime,
        'operid': operid, 'opername': opername,
      };
}
