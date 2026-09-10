import 'package:flutter/material.dart';
import 'package:flutter_deer/components/spec_cook_sheet.dart';
import 'package:flutter_deer/db/entity/db_table_name.dart';
import 'package:flutter_deer/db/entity/product_type_entity.dart';
import 'package:flutter_deer/db/entity/product_unit_entity.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/table_download_manager.dart';
import 'package:flutter_deer/pages/order/order_repository.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/util/user_helper.dart';

/// 品牌红（对齐本项目 spec_cook_sheet 等较新弹窗组件）
const Color _kBrandRed = Color(0xFFE63F31);

/// 临时菜录入结果（对齐 smdcapp TemporaryDishesPop2 确认后 PopupResult.goodsBean 核心字段）
class TemporaryDishResult {
  const TemporaryDishResult({
    required this.name,
    required this.typeid,
    required this.typename,
    required this.price,
    required this.qty,
    required this.unit,
    required this.tpdishid,
    required this.tpdishidzd,
    required this.tpdscflag,
    required this.cookText,
    required this.cookExtra,
    required this.remark,
    required this.goOrder,
  });

  /// 菜品名称
  final String name;

  /// 分类ID
  final String typeid;

  /// 分类名称
  final String typename;

  /// 售价
  final double price;

  /// 数量
  final int qty;

  /// 单位
  final String unit;

  /// 厨打方案1（-1=不打印，对齐 smdcapp tpdishid）
  final String tpdishid;

  /// 厨打方案2（对齐 smdcapp tpdishidzd）
  final String tpdishidzd;

  /// 是否可折 1=可折（对齐 smdcapp tpdscflag）
  final int tpdscflag;

  /// 做法描述文本
  final String cookText;

  /// 做法加价
  final double cookExtra;

  /// 备注（自定义备注 + 快捷备注拼接，对齐 smdcapp etMark + remark）
  final String remark;

  /// 是否去下单页（true=下单按钮，false=加入购物车）
  final bool goOrder;
}

/// 临时菜弹窗（对齐 smdcapp TemporaryDishesPop2）
///
/// 字段：名称/分类/价格/数量/出品档口x2/单位/做法/可折/保存资料/备注，
/// 确认按钮：加入购物车(0) / 下单(1)，校验与保存资料流程对齐 smdcapp confirm()。
class TemporaryDishSheet extends StatefulWidget {
  const TemporaryDishSheet({super.key});

  /// 显示临时菜弹窗，返回录入结果（取消返回 null）
  static Future<TemporaryDishResult?> show(BuildContext context) {
    return showModalBottomSheet<TemporaryDishResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TemporaryDishSheet(),
    );
  }

  @override
  State<TemporaryDishSheet> createState() => _TemporaryDishSheetState();
}

class _TemporaryDishSheetState extends State<TemporaryDishSheet> {
  final TextEditingController _nameCtrl =
      TextEditingController(text: '临时菜');
  final TextEditingController _priceCtrl = TextEditingController(text: '1');
  final TextEditingController _numCtrl = TextEditingController(text: '1');
  final TextEditingController _markCtrl = TextEditingController();

  /// 分类列表（对齐 smdcapp ProductTypeHelper.getProuctTypeAll）
  List<ProductTypeEntity> _types = <ProductTypeEntity>[];
  ProductTypeEntity? _type;

  /// 单位列表（对齐 smdcapp PublicHelper.getProuctUnit）
  List<ProductUnitEntity> _units = <ProductUnitEntity>[];
  ProductUnitEntity? _unit;

  /// 出品档口列表（对齐 smdcapp getKitchenList(2)，首项固定“不打印” dishid=-1）
  List<KitchenItem> _kitchens1 = <KitchenItem>[];
  List<KitchenItem> _kitchens2 = <KitchenItem>[];
  KitchenItem? _kitchen1;
  KitchenItem? _kitchen2;

  /// 快捷备注（对齐 smdcapp PublicHelper.getReason("06")）
  final List<_RemarkItem> _remarks = <_RemarkItem>[];

  /// 是否可折（对齐 smdcapp cb_print，默认开）
  bool _canDiscount = true;

  /// 保存资料（对齐 smdcapp cb_save，默认关；主设备模式不可开）
  bool _saveInfo = false;

  /// 做法描述（对齐 smdcapp tv_cook）
  String _cookText = '';
  double _cookExtra = 0;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _numCtrl.dispose();
    _markCtrl.dispose();
    super.dispose();
  }

  /// 加载分类/单位/档口/快捷备注（对齐 smdcapp getDangkou）
  ///
  /// 全部经 [TableDownloadManager.readTableData] 读取（Web 走内存缓存、
  /// 移动端走 SQLite），不可直连 DAO：Web 平台 sqflite 抛 UnsupportedError
  /// 会被下方 catch 吞掉，导致 setState 不执行、所有下拉为空。
  /// 分类本地缓存为空时回退点菜页同源接口（OrderRepository.fetchCategories），
  /// 保证“点菜页有分类则临时菜弹窗必有分类”。
  Future<void> _loadData() async {
    final int spid = UserHelper.getSpid();
    final int sid = UserHelper.getSid();
    try {
      // 对齐 smdcapp ProductTypeDao.queryAllType：stopflag=0 and status=1 and mobileshowflag=1
      final List<Map<String, dynamic>> typeRows =
          await TableDownloadManager.readTableData(DbTableName.tBiType);
      final List<ProductTypeEntity> types = typeRows
          .where((Map<String, dynamic> r) =>
              _i(r['stopflag']) == 0 &&
              _i(r['status']) == 1 &&
              _i(r['mobileshowflag']) == 1)
          .map(_typeFromRow)
          .toList()
        ..sort((ProductTypeEntity a, ProductTypeEntity b) =>
            a.isort.compareTo(b.isort));
      if (types.isEmpty) {
        types.addAll(await _fetchTypesFallback());
      }
      // 对齐 smdcapp ProductUnitDao.queryAll：status = 1
      final List<Map<String, dynamic>> unitRows =
          await TableDownloadManager.readTableData(DbTableName.tBiUnit);
      final List<ProductUnitEntity> units = unitRows
          .where((Map<String, dynamic> r) => _i(r['status']) == 1)
          .map(_unitFromRow)
          .toList();
      // 对齐 smdcapp ReasonInfoDao.queryByTypeId：typeid + status=1 + spid + sid
      final List<Map<String, dynamic>> remarkRows =
          await TableDownloadManager.readTableData(DbTableName.tBiReasonInfo);
      final List<_RemarkItem> remarks = remarkRows
          .where((Map<String, dynamic> r) =>
              r['typeid']?.toString() == '06' &&
              _i(r['status']) == 1 &&
              _i(r['spid']) == spid &&
              _i(r['sid']) == sid)
          .map((Map<String, dynamic> r) =>
              _RemarkItem(r['value']?.toString() ?? ''))
          .toList();
      final List<KitchenItem> kitchens = await OrderRepository.fetchKitchenList();
      if (!mounted) return;
      setState(() {
        _types = types;
        if (_types.isNotEmpty) _type = _types[0];
        _units = units;
        if (_units.isNotEmpty) _unit = _units[0];
        // 对齐 smdcapp：档口首项固定“不打印”(dishid=-1) 且默认选中
        _kitchens1 = <KitchenItem>[const KitchenItem(dishid: '-1', name: '不打印'), ...kitchens];
        _kitchens2 = <KitchenItem>[const KitchenItem(dishid: '-1', name: '不打印'), ...kitchens];
        _kitchen1 = _kitchens1[0];
        _kitchen2 = _kitchens2[0];
        _remarks.addAll(remarks);
      });
    } catch (_) {
      // 数据加载失败静默处理，确认时按空校验提示
    }
  }

  /// 分类本地缓存为空时的回退（与点菜页同源：本地 t_bi_type → getTypeList 实时接口）
  Future<List<ProductTypeEntity>> _fetchTypesFallback() async {
    try {
      final List<DishCategory> cats = await OrderRepository.fetchCategories();
      return cats
          .map((DishCategory c) => ProductTypeEntity(
                typeid: c.typeid,
                name: c.name,
                isort: c.isort,
              ))
          .toList();
    } catch (_) {
      return <ProductTypeEntity>[];
    }
  }

  /// 容忍文本/数字混合的基础数据行转 int
  int _i(dynamic v) => v is int
      ? v
      : (v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0));

  ProductTypeEntity _typeFromRow(Map<String, dynamic> r) => ProductTypeEntity(
        id: _i(r['id']),
        spid: _i(r['spid']),
        sid: _i(r['sid']),
        status: _i(r['status']),
        isort: _i(r['isort']),
        stopflag: _i(r['stopflag']),
        typeid: r['typeid']?.toString() ?? '',
        code: r['code']?.toString() ?? '',
        name: r['name']?.toString() ?? '',
        parenttypeid: r['parenttypeid']?.toString() ?? '',
        level: _i(r['level']),
        typeid1: r['typeid1']?.toString() ?? '',
        mobileshowflag: _i(r['mobileshowflag']),
      );

  ProductUnitEntity _unitFromRow(Map<String, dynamic> r) => ProductUnitEntity(
        id: _i(r['id']),
        spid: _i(r['spid']),
        sid: _i(r['sid']),
        status: _i(r['status']),
        isort: _i(r['isort']),
        stopflag: _i(r['stopflag']),
        unitid: r['unitid']?.toString() ?? '',
        name: r['name']?.toString() ?? '',
      );

  // ==================== 交互 ====================

  /// 数量加减（对齐 smdcapp img_minus/img_add，上限 999.99）
  void _stepNum(int delta) {
    double num = double.tryParse(_numCtrl.text) ?? 0;
    num += delta;
    if (num < 0) num = 0;
    if (num > 999.99) {
      Toast.show('最大数量999.99');
      return;
    }
    setState(() {
      _numCtrl.text = num == num.roundToDouble()
          ? num.toInt().toString()
          : num.toString();
    });
  }

  /// 保存资料开关（对齐 smdcapp ll_save：主设备模式无法保存）
  void _toggleSave() {
    if (ConnectionManager.pcAlive) {
      Toast.show('主设备模式无法保存');
      return;
    }
    setState(() => _saveInfo = !_saveInfo);
  }

  /// 选择做法（对齐 smdcapp ll_cook → TemporaryDishesCookPopup2，数据源为全局做法）
  Future<void> _pickCook() async {
    final List<DishCookGroup> publicCooks =
        await OrderRepository.fetchPublicCooks();
    if (!mounted) return;
    if (publicCooks.isEmpty) {
      Toast.show('没有做法数据');
      return;
    }
    final double price = double.tryParse(_priceCtrl.text) ?? 0;
    final CookModifyResult? result = await SpecCookSheet.showModify(
      context,
      dishName: _nameCtrl.text.trim().isEmpty ? '临时菜' : _nameCtrl.text.trim(),
      unitPrice: price,
      specData: DishSpecData(cookdata: publicCooks),
      currentSpecText: _cookText,
    );
    if (result != null && mounted) {
      setState(() {
        _cookText = result.cookText;
        _cookExtra = result.cookExtra;
      });
    }
  }

  /// 通用单选下拉（对齐 smdcapp showPopupWindow popup_select）
  Future<void> _showPickSheet<T>({
    required String title,
    required List<T> items,
    required String Function(T) labelOf,
    required T? selected,
    required ValueChanged<T> onPick,
  }) async {
    if (items.isEmpty) {
      Toast.show('没有查询到数据');
      return;
    }
    final T? picked = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        final bool dark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.4,
          ),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF242526) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: dark
                          ? const Color(0xFF3A3C3D)
                          : const Color(0xFFF2F3F5),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 3.5,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _kBrandRed,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: dark
                                  ? Colors.white
                                  : const Color(0xFF1D2129))),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 36, minHeight: 36),
                      icon: Icon(Icons.close,
                          size: 20,
                          color: dark
                              ? const Color(0xFF999999)
                              : const Color(0xFF86909C)),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: dark
                          ? const Color(0xFF3A3C3D)
                          : const Color(0xFFF2F3F5)),
                  itemBuilder: (BuildContext ctx, int i) {
                    final T item = items[i];
                    final bool checked = identical(item, selected) ||
                        labelOf(item) ==
                            (selected == null ? '' : labelOf(selected));
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(ctx).pop(item),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        color: checked
                            ? (dark
                                ? const Color(0xFF3D2826)
                                : const Color(0xFFFFF1F0))
                            : null,
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                labelOf(item),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: checked
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: checked
                                      ? _kBrandRed
                                      : (dark
                                          ? Colors.white
                                          : const Color(0xFF1D2129)),
                                ),
                              ),
                            ),
                            if (checked)
                              const Icon(Icons.check,
                                  size: 18, color: _kBrandRed),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => onPick(picked));
    }
  }

  // ==================== 确认 ====================

  /// 确认（对齐 smdcapp confirm(type)：0=加入购物车 1=下单）
  Future<void> _confirm(int type) async {
    if (_submitting) return;
    final String name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      Toast.show('请输入菜品名称');
      return;
    }
    if (_type == null) {
      Toast.show('请选择菜品分类');
      return;
    }
    final double? price = double.tryParse(_priceCtrl.text.trim());
    if (price == null) {
      Toast.show('价格格式错误');
      return;
    }
    final double? num = double.tryParse(_numCtrl.text.trim());
    if (num == null || num <= 0) {
      Toast.show('请输入菜品数量');
      return;
    }
    if (_kitchen1 == null) {
      Toast.show('请选择出品档口');
      return;
    }
    if (_kitchen2 == null) {
      Toast.show('请选择出品档口二');
      return;
    }
    if (_unit == null) {
      Toast.show('请选择菜品单位');
      return;
    }

    // 保存资料（对齐 smdcapp：cbSave && !pcAlive → getBarcode + addProduct）
    if (_saveInfo && !ConnectionManager.pcAlive) {
      setState(() => _submitting = true);
      try {
        final String barcode =
            await OrderRepository.fetchBarcode(_type!.typeid);
        if (barcode.isEmpty) {
          Toast.show('保存菜品异常：获取菜品条码失败');
          return;
        }
        final Map<String, dynamic> resp =
            await OrderRepository.addTempProduct(<String, dynamic>{
          'timetype': '1',
          'sid': UserHelper.getSidStr(),
          'spid': UserHelper.getSpidStr(),
          'barcode': barcode,
          'name': name,
          'typeid': _type!.typeid,
          'unit': _unit!.name,
          'sellprice': price.toString(),
          'dscflag': _canDiscount ? '1' : '0',
          'printflag': '1',
          'labelflag': '1',
          'pointflag': '1',
          'minsaleflag': '1',
          'presentflag': '1',
          'curflag': '0',
          'stockflag': '0',
          'eatinstoreflag': '0',
          'recommendflag': '0',
          'pcshowflag': '1',
          'scanshowflag': '1',
          'padshowflag': '1',
          'mobileshowflag': '1',
          'saledateflag': '1',
          'addsellqty': '1',
          'startsellqty': '0.0',
        });
        // requestForm 在 retcode!=0 时抛异常（toString 即 retmsg），此处仅防御性检查
        final dynamic retcode = resp['retcode'];
        if (retcode != null && retcode.toString() != '0') {
          Toast.show(resp['retmsg']?.toString() ?? '保存菜品资料失败');
          return;
        }
      } catch (e) {
        Toast.show('$e');
        return;
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
    }

    if (!mounted) return;
    // 快捷备注拼接（对齐 smdcapp：选中项 value 逗号拼接）
    final String quickRemark = _remarks
        .where((_RemarkItem r) => r.checked)
        .map((_RemarkItem r) => r.value)
        .join(',');
    final String remark = _markCtrl.text.trim() + quickRemark;
    Navigator.of(context).pop(TemporaryDishResult(
      name: name,
      typeid: _type!.typeid,
      typename: _type!.name,
      price: price,
      qty: num.toInt() < 1 ? 1 : num.toInt(),
      unit: _unit!.name,
      tpdishid: _kitchen1!.dishid,
      tpdishidzd: _kitchen2!.dishid,
      tpdscflag: _canDiscount ? 1 : 0,
      cookText: _cookText,
      cookExtra: _cookExtra,
      remark: remark,
      goOrder: type == 1,
    ));
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _buildHeader(isDark),
            // 表单区
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: 12),
                    _buildInputRow(
                      isDark: isDark,
                      label: '菜品名称',
                      required: true,
                      child: TextField(
                        controller: _nameCtrl,
                        maxLength: 20,
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              isDark ? Colors.white : const Color(0xFF1D2129),
                        ),
                        decoration: const InputDecoration(
                          hintText: '请输入菜品名称',
                          hintStyle:
                              TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
                          border: InputBorder.none,
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                    ),
                    _buildSelectRow(
                      isDark: isDark,
                      label: '菜品分类',
                      required: true,
                      value: _type?.name,
                      hint: '请选择菜品分类',
                      onTap: () => _showPickSheet<ProductTypeEntity>(
                        title: '菜品分类',
                        items: _types,
                        labelOf: (ProductTypeEntity e) => e.name,
                        selected: _type,
                        onPick: (ProductTypeEntity e) => _type = e,
                      ),
                    ),
                    _buildInputRow(
                      isDark: isDark,
                      label: '菜品价格',
                      required: true,
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              isDark ? Colors.white : const Color(0xFF1D2129),
                        ),
                        decoration: const InputDecoration(
                          hintText: '请输入菜品价格',
                          hintStyle:
                              TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    // 购买数量（对齐 smdcapp img_minus + et_num + img_add）
                    _buildRow(
                        isDark: isDark,
                        label: '购买数量',
                        required: true,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            GestureDetector(
                              onTap: () => _stepNum(-1),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF666666)
                                        : const Color(0xFFC9CDD4),
                                    width: 1.2,
                                  ),
                                ),
                                child: Icon(Icons.remove,
                                    size: 13,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF86909C)),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: TextField(
                                controller: _numCtrl,
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                maxLength: 6,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1D2129),
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  counterText: '',
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _stepNum(1),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: const BoxDecoration(
                                  color: _kBrandRed,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add,
                                    size: 13, color: Colors.white),
                              ),
                            ),
                          ],
                        )),
                    _buildSelectRow(
                      isDark: isDark,
                      label: '出品档口',
                      required: true,
                      value: _kitchen1?.name,
                      hint: '请选择档口',
                      onTap: () => _showPickSheet<KitchenItem>(
                        title: '出品档口',
                        items: _kitchens1,
                        labelOf: (KitchenItem e) => e.name,
                        selected: _kitchen1,
                        onPick: (KitchenItem e) => _kitchen1 = e,
                      ),
                    ),
                    _buildSelectRow(
                      isDark: isDark,
                      label: '出品档口二',
                      required: true,
                      value: _kitchen2?.name,
                      hint: '请选择档口二',
                      onTap: () => _showPickSheet<KitchenItem>(
                        title: '出品档口二',
                        items: _kitchens2,
                        labelOf: (KitchenItem e) => e.name,
                        selected: _kitchen2,
                        onPick: (KitchenItem e) => _kitchen2 = e,
                      ),
                    ),
                    _buildSelectRow(
                      isDark: isDark,
                      label: '商品单位',
                      required: true,
                      value: _unit?.name,
                      hint: '请选择菜品单位',
                      onTap: () {
                        if (_units.isEmpty) {
                          Toast.show('没有查询到单位数据');
                          return;
                        }
                        _showPickSheet<ProductUnitEntity>(
                          title: '商品单位',
                          items: _units,
                          labelOf: (ProductUnitEntity e) => e.name,
                          selected: _unit,
                          onPick: (ProductUnitEntity e) => _unit = e,
                        );
                      },
                    ),
                    _buildSelectRow(
                      isDark: isDark,
                      label: '商品做法',
                      value: _cookText.isEmpty ? null : _cookText,
                      hint: '请选择菜品做法',
                      onTap: _pickCook,
                    ),
                    // 是否可折 + 保存资料（对齐 smdcapp cb_print / cb_save）
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _rowDecoration(isDark),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Row(
                              children: <Widget>[
                                Text('是否可折：',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF1D2129))),
                                _buildSwitch(_canDiscount, isDark,
                                    () => setState(() => _canDiscount = !_canDiscount)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _toggleSave,
                              child: Row(
                                children: <Widget>[
                                  Text('保存资料：',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1D2129))),
                                  _buildSwitch(_saveInfo, isDark, _toggleSave),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 备注区（对齐 smdcapp view_line + 备注 + et_mark + rv_mark）
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 10),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 3.5,
                            height: 14,
                            decoration: BoxDecoration(
                              color: _kBrandRed,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('备注',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1D2129))),
                        ],
                      ),
                    ),
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _rowDecoration(isDark),
                      child: TextField(
                        controller: _markCtrl,
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              isDark ? Colors.white : const Color(0xFF1D2129),
                        ),
                        decoration: const InputDecoration(
                          hintText: '请输入自定义备注',
                          hintStyle:
                              TextStyle(fontSize: 14, color: Color(0xFFC9CDD4)),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 快捷备注网格（对齐 smdcapp rv_mark grid spanCount=4）
                    if (_remarks.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _remarks
                            .map((_RemarkItem r) => GestureDetector(
                                  onTap: () =>
                                      setState(() => r.checked = !r.checked),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: r.checked
                                          ? (isDark
                                              ? const Color(0xFF3D2826)
                                              : const Color(0xFFFFF1F0))
                                          : (isDark
                                              ? const Color(0xFF3A3C3D)
                                              : const Color(0xFFF5F5F5)),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: r.checked
                                            ? _kBrandRed
                                            : (isDark
                                                ? const Color(0xFF4A4C4D)
                                                : const Color(0xFFE5E6EB)),
                                        width: r.checked ? 1 : 0.5,
                                      ),
                                    ),
                                    child: Text(
                                      r.value,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: r.checked
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: r.checked
                                            ? _kBrandRed
                                            : (isDark
                                                ? Colors.white
                                                : const Color(0xFF333333)),
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            // 底部按钮（对齐 smdcapp tv_order 灰 + tv_add_cart 红）
            _buildBottomBar(isDark),
          ],
        ),
      ),
    );
  }

  /// 标题栏（红条 + 添加临时菜 + 圆形关闭，对齐本项目统一弹窗风格）
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF2F3F5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: _kBrandRed,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '添加临时菜',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1D2129),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 18,
                color: isDark ? Colors.white70 : const Color(0xFF86909C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏（次按钮下单 + 主按钮加入购物车，对齐 spec_cook_sheet 按钮风格）
  Widget _buildBottomBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242526) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF2F3F5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onTap: _submitting ? null : () => _confirm(1),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3C3D)
                      : const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _kBrandRed),
                ),
                alignment: Alignment.center,
                child: const Text('下单',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kBrandRed)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _submitting ? null : () => _confirm(0),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFF0503F), _kBrandRed],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: _kBrandRed.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white)),
                      )
                    : const Text('加入购物车',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 表单行统一背景（浅灰圆角，对齐 spec_cook_sheet 输入区风格）
  BoxDecoration _rowDecoration(bool isDark) => BoxDecoration(
        color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
      );

  /// 缩小版开关（适配表单行高）
  Widget _buildSwitch(bool value, bool isDark, VoidCallback onChanged) {
    return SizedBox(
      height: 22,
      width: 38,
      child: FittedBox(
        child: Switch(
          value: value,
          activeColor: _kBrandRed,
          activeTrackColor: _kBrandRed.withValues(alpha: 0.35),
          inactiveThumbColor: isDark ? const Color(0xFF999999) : Colors.white,
          inactiveTrackColor:
              isDark ? const Color(0xFF666666) : const Color(0xFFE5E6EB),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (_) => onChanged(),
        ),
      ),
    );
  }

  /// 输入行（对齐 smdcapp ll_name/ll_price 行样式）
  Widget _buildInputRow({
    required bool isDark,
    required String label,
    bool required = false,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _rowDecoration(isDark),
      child: Row(
        children: <Widget>[
          if (required)
            const Text('*',
                style: TextStyle(fontSize: 14, color: _kBrandRed)),
          Text('$label：',
              style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1D2129))),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// 下拉选择行（对齐 smdcapp ll_type/ll_dang_kou/ll_unit 行样式）
  Widget _buildSelectRow({
    required bool isDark,
    required String label,
    bool required = false,
    required String? value,
    required String hint,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _rowDecoration(isDark),
        child: Row(
          children: <Widget>[
            if (required)
              const Text('*',
                  style: TextStyle(fontSize: 14, color: _kBrandRed)),
            Text('$label：',
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF1D2129))),
            Expanded(
              child: Text(
                value == null || value.isEmpty ? hint : value,
                style: TextStyle(
                  fontSize: 14,
                  color: value == null || value.isEmpty
                      ? const Color(0xFFC9CDD4)
                      : (isDark ? Colors.white : const Color(0xFF1D2129)),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down,
                size: 20,
                color: isDark ? const Color(0xFF999999) : const Color(0xFF86909C)),
          ],
        ),
      ),
    );
  }

  /// 自定义内容行
  Widget _buildRow({
    required bool isDark,
    required String label,
    bool required = false,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _rowDecoration(isDark),
      child: Row(
        children: <Widget>[
          if (required)
            const Text('*',
                style: TextStyle(fontSize: 14, color: _kBrandRed)),
          Text('$label：',
              style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1D2129))),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 快捷备注项（对齐 smdcapp ReasonList.ListBean value + isCheck）
class _RemarkItem {
  _RemarkItem(this.value);

  final String value;
  bool checked = false;
}
