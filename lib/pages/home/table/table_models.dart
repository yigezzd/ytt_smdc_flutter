import 'package:flutter/material.dart';
import 'package:sp_util/sp_util.dart';

/// 桌台状态（对齐 smdcapp TableStatusEnum）
///
/// code 与后端 tablestatus 字段一致：0空闲 1待下单 2待结算 3已预结 4待清台
enum TableStatus {
  /// 0 空闲
  idle,

  /// 1 待下单
  waitingOrder,

  /// 2 待结算
  waitingSettle,

  /// 3 已预结
  preSettled,

  /// 4 待清台
  waitingClear;

  /// 后端状态码
  int get code => index;

  /// 根据后端 code 解析（越界/异常一律按空闲处理）
  static TableStatus fromCode(int? code) {
    if (code == null || code < 0 || code >= TableStatus.values.length) {
      return TableStatus.idle;
    }
    return TableStatus.values[code];
  }
}

extension TableStatusExtension on TableStatus {
  /// 状态文案（对齐 smdcapp）
  String get label =>
      <String>['空闲', '待下单', '待结算', '已预结', '待清台'][index];

  /// 状态主题色（读取参数配置，未配置时取 smdcapp 默认色）
  Color get color => TableColorConfig.colorOf(this);

  /// 卡片背景色（主题色与白色按 30% 混合，对齐 smdcapp getTabGradientColor(0.3f)）
  Color get bgColor => TableColorConfig.bgColorOf(this);

  /// 是否为"无底色"样式(空闲状态仅显示灰色文字)
  bool get isPlain => this == TableStatus.idle;
}

/// 桌台状态颜色配置（对齐 smdcapp SpUtils 的桌台颜色参数）
///
/// 颜色以十六进制字符串存储在本地（key 与 smdcapp 一致），
/// 未配置或非法时回退到 smdcapp 默认色。
class TableColorConfig {
  TableColorConfig._();

  /// 各状态对应的存储 key（顺序与 [TableStatus] 一致）
  static const List<String> _keys = <String>[
    'idleFlag', // 空闲
    'pendingOrderFlag', // 待下单
    'pendingCheckoutFlag', // 待结算
    'preCheckoutFlag', // 已预结
    'pendingClearFlag', // 待清台
  ];

  /// smdcapp 默认色
  static const List<String> _defaults = <String>[
    '#D1D1D1', // 空闲-灰
    '#5672FF', // 待下单-蓝
    '#E13426', // 待结算-红
    '#00C261', // 已预结-绿
    '#4F5A6A', // 待清台-深灰
  ];

  static final RegExp _colorReg =
      RegExp(r'^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$');

  /// 读取某状态的主题色
  static Color colorOf(TableStatus status) {
    final int i = status.index;
    final String stored = SpUtil.getString(_keys[i]) ?? '';
    final String hex =
        (stored.isEmpty || !_colorReg.hasMatch(stored)) ? _defaults[i] : stored;
    return _parseHex(hex);
  }

  /// 读取某状态的卡片背景色（主题色 30% + 白色 70%）
  static Color bgColorOf(TableStatus status) => _blendWhite(colorOf(status), 0.3);

  /// 解析 #RRGGBB / #AARRGGBB（与 smdcapp Color.parseColor 一致）
  static Color _parseHex(String hex) {
    String v = hex.replaceFirst('#', '');
    if (v.length == 6) {
      v = 'FF$v';
    }
    return Color(int.parse(v, radix: 16));
  }

  /// 与白色按比例混合（对齐 smdcapp getTabGradientColor）
  static Color _blendWhite(Color c, double ratio) {
    int ch(int v) => (v * ratio + 255 * (1 - ratio)).round().clamp(0, 255);
    return Color.fromARGB(255, ch(c.red), ch(c.green), ch(c.blue));
  }
}

/// 区域（对齐 smdcapp AreaBean）
class TableArea {
  TableArea({
    required this.areaid,
    required this.name,
    this.tabletotal = 0,
    this.statusCounts = const <int, int>{},
  });

  factory TableArea.fromJson(Map<String, dynamic> json) {
    final Map<int, int> counts = <int, int>{};
    final dynamic statusList = json['areatablestatuslist'];
    if (statusList is List) {
      for (final dynamic item in statusList) {
        if (item is Map) {
          final int status = _toInt(item['tablestatus']);
          final int total = _toInt(item['tablestatustotal']);
          counts[status] = (counts[status] ?? 0) + total;
        }
      }
    }
    return TableArea(
      areaid: json['areaid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      tabletotal: _toInt(json['tabletotal']),
      statusCounts: counts,
    );
  }

  /// 区域id（"全部"为合成项，areaid='-1'）
  final String areaid;

  /// 区域名称
  final String name;

  /// 区域内桌台总数
  final int tabletotal;

  /// 区域内各状态数量：key=状态码 value=数量
  final Map<int, int> statusCounts;

  /// 是否为合成的"全部"项
  bool get isAll => areaid == '-1';
}

/// 桌台开台详情（对齐 smdcapp TableDetailBean，即 TableInfoBean.tmp）
class TableDetail {
  TableDetail({
    required this.tablestatus,
    this.amt = 0,
    this.personnum = 0,
    this.saleid = '',
    this.billdate = '',
    this.unitableid = '',
    this.unitableno = '',
    this.unitablename = '',
    this.uniflowno = '',
    this.lockflag = 0,
    this.hangflag = 0,
    this.preprintflag = 0,
    this.serverid = '',
    this.servername = '',
    this.remark = '',
  });

  factory TableDetail.fromJson(Map<String, dynamic> json) {
    return TableDetail(
      tablestatus: _toInt(json['tablestatus']),
      amt: _toDouble(json['amt']),
      personnum: _toInt(json['personnum']),
      saleid: json['saleid']?.toString() ?? '',
      billdate: json['billdate']?.toString() ?? '',
      unitableid: json['unitableid']?.toString() ?? '',
      unitableno: json['unitableno']?.toString() ?? '',
      unitablename: json['unitablename']?.toString() ?? '',
      uniflowno: json['uniflowno']?.toString() ?? '',
      lockflag: _toInt(json['lockflag']),
      hangflag: _toInt(json['hangflag']),
      preprintflag: _toInt(json['preprintflag']),
      serverid: json['serverid']?.toString() ?? '',
      servername: json['servername']?.toString() ?? '',
      remark: json['remark']?.toString() ?? '',
    );
  }

  /// 桌台状态：0空闲 1待下单 2待结算 3已预结 4待清台
  final int tablestatus;

  /// 消费金额（实收）
  final double amt;

  /// 就餐人数
  final int personnum;

  /// 主单id
  final String saleid;

  /// 开台时间
  final String billdate;

  /// 并台主台标识
  final String unitableid;

  /// 并台桌号
  final String unitableno;

  /// 并台桌名
  final String unitablename;

  /// 并台流水号
  final String uniflowno;

  /// 锁台标识：1锁住 0未锁
  final int lockflag;

  /// 挂单标识：1有挂单
  final int hangflag;

  /// 预打印标识：1已预打
  final int preprintflag;

  final String serverid;
  final String servername;
  final String remark;

  /// 序列化为 JSON（对齐 smdcapp TableDetailBean 全字段，用于 PC 模式接口提交）
  Map<String, dynamic> toJson() => <String, dynamic>{
        'tablestatus': tablestatus,
        'amt': amt,
        'personnum': personnum,
        'saleid': saleid,
        'billdate': billdate,
        'unitableid': unitableid,
        'unitableno': unitableno,
        'unitablename': unitablename,
        'uniflowno': uniflowno,
        'lockflag': lockflag,
        'hangflag': hangflag,
        'preprintflag': preprintflag,
        'serverid': serverid,
        'servername': servername,
        'remark': remark,
      };
}

/// 桌台信息（对齐 smdcapp TableInfoBean）
class TableInfo {
  TableInfo({
    required this.tableid,
    required this.name,
    this.code = '',
    this.areaid = '',
    this.areaname = '',
    this.person = 0,
    this.unicount = 0,
    this.tmp,
    this.selected = false,
    this.rawJson,
  });

  factory TableInfo.fromJson(Map<String, dynamic> json) {
    final dynamic tmpJson = json['tmp'];
    return TableInfo(
      tableid: json['tableid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      areaid: json['areaid']?.toString() ?? '',
      areaname: json['areaname']?.toString() ?? '',
      person: _toInt(json['person']),
      unicount: _toInt(json['unicount']),
      tmp: tmpJson is Map
          ? TableDetail.fromJson(tmpJson.cast<String, dynamic>())
          : null,
      rawJson: json,
    );
  }

  /// 桌台唯一id
  final String tableid;

  /// 桌号，如 A03
  final String name;

  /// 桌台编码
  final String code;

  /// 所属区域id
  final String areaid;

  /// 所属区域名称
  final String areaname;

  /// 桌台容量（可坐人数）
  final int person;

  /// 并台数量
  final int unicount;

  /// 开台详情（空闲时为 null）
  final TableDetail? tmp;

  /// 是否选中(右上角绿色对勾)
  bool selected;

  /// 原始 JSON（服务端返回的完整数据，用于 PC 模式接口回传，对齐 smdcapp objectClone）
  final Map<String, dynamic>? rawJson;

  /// 展示用状态（取 tmp.tablestatus，空闲无 tmp 时为 0）
  TableStatus get status => TableStatus.fromCode(tmp?.tablestatus ?? 0);

  /// 是否空闲
  bool get isIdle => tmp == null || (tmp!.tablestatus == 0);

  /// 是否锁台
  bool get isLocked => tmp?.lockflag == 1;

  /// 是否有挂单
  bool get isHang => tmp?.hangflag == 1;

  /// 是否已预打
  bool get isPrePrint => tmp?.preprintflag == 1;

  /// 是否并台（含其它子台）
  bool get isMerged => tmp != null && tmp!.unitableno.isNotEmpty;

  /// 并台提示文案，如 "并01"
  String? get mergeNote {
    if (!isMerged) {
      return null;
    }
    final String no =
        tmp!.uniflowno.isNotEmpty ? tmp!.uniflowno : tmp!.unitableno;
    return '并$no';
  }

  /// 人数展示：空闲显示容量，其它显示 "就餐人数/容量"
  String get personText {
    if (isIdle) {
      return person > 0 ? '$person' : '';
    }
    return '${tmp?.personnum ?? 0}/$person';
  }

  /// 金额展示（空闲/待清台不显示）
  String? get amountText {
    final TableStatus s = status;
    if (s == TableStatus.idle || s == TableStatus.waitingClear) {
      return null;
    }
    final double amt = tmp?.amt ?? 0;
    if (s == TableStatus.preSettled && amt <= 0) {
      return null;
    }
    return amt.toStringAsFixed(2);
  }

  /// 开台时间（HH:mm），空闲无时间
  String? get timeText {
    final String billdate = tmp?.billdate ?? '';
    if (isIdle || billdate.isEmpty) {
      return null;
    }
    final DateTime? dt = DateTime.tryParse(billdate.replaceAll(' ', 'T'));
    if (dt == null) {
      return null;
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
  }

  /// 序列化为 JSON（对齐 smdcapp TableInfoBean 全字段，用于 PC 模式接口提交）
  ///
  /// 优先使用原始 JSON（保留服务端返回的所有字段），
  /// 避免手动构建时缺少字段导致服务端 NullReferenceException。
  Map<String, dynamic> toJson() {
    if (rawJson != null) {
      return Map<String, dynamic>.from(rawJson!);
    }
    return <String, dynamic>{
      'tableid': tableid,
      'name': name,
      'code': code,
      'areaid': areaid,
      'areaname': areaname,
      'person': person,
      'unicount': unicount,
      'tablestatus': '${tmp?.tablestatus ?? 0}',
      'tmp': tmp?.toJson(),
    };
  }
}

int _toInt(dynamic v) {
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is num) {
    return v.toDouble();
  }
  return double.tryParse(v?.toString() ?? '') ?? 0;
}
