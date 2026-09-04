import 'dart:convert';

import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/table_download_manager.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';
import 'package:flutter_deer/util/user_helper.dart';
import 'package:sp_util/sp_util.dart';

/// 菜品分类模型（对齐 smdcapp DishesTypeBean.DataBean.children）
class DishCategory {
  DishCategory({
    required this.typeid,
    required this.name,
    this.isort = 0,
    this.stopflag = 0,
  });

  factory DishCategory.fromJson(Map<String, dynamic> json) {
    return DishCategory(
      typeid: json['typeid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      isort: _toInt(json['isort']),
      stopflag: _toInt(json['stopflag']),
    );
  }

  final String typeid;
  final String name;
  final int isort;
  final int stopflag;
}

/// 出品档口模型（对齐 smdcapp KitchenBean.ListBean 核心字段）
class KitchenItem {
  const KitchenItem({required this.dishid, required this.name});

  /// 厨打方案ID（-1=不打印）
  final String dishid;
  final String name;
}

/// 商品模型（对齐 smdcapp ProductBean 核心字段）
class DishProduct {
  DishProduct({
    required this.productid,
    required this.name,
    required this.sellprice,
    this.typeid = '',
    this.typename = '',
    this.unit = '份',
    this.imageurl = '',
    this.barcode = '',
    this.helpcode = '',
    this.cookflag = 0,
    this.specflag = 0,
    this.combflag = 0,
    this.curflag = 0,
    this.weighflag = 0,
    this.sellclearflag = 0,
    this.recommendflag = 0,
    this.stockqty = 0,
    this.isort = 0,
    this.typeproisort = 0,
    this.mprice1 = 0,
    this.mprice2 = 0,
    this.mprice3 = 0,
    this.dscflag = 1,
    this.maxsellqty = 0,
    this.printflag = 1,
    this.pointflag = 0,
    this.minsaleflag = 1,
    this.presentflag = 0,
    this.stockflag = 0,
    this.inprice = 0,
    this.startsellqty = 0,
    this.addsellqty = 0,
    this.servicefeeflag = 0,
    this.moreeatflag = 0,
    this.combtype = 0,
    this.mobileshowflag = 1,
    this.datetype = 0,
    this.begindate = '',
    this.enddate = '',
  });

  factory DishProduct.fromJson(Map<String, dynamic> json) {
    return DishProduct(
      productid: json['productid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sellprice: _toDouble(json['sellprice']),
      typeid: json['typeid']?.toString() ?? '',
      typename: json['typename']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '份',
      imageurl: json['imageurl']?.toString() ?? '',
      barcode: json['barcode']?.toString() ?? '',
      helpcode: json['helpcode']?.toString() ?? '',
      cookflag: _toInt(json['cookflag']),
      specflag: _toInt(json['specflag']),
      combflag: _toInt(json['combflag']),
      curflag: _toInt(json['curflag']),
      weighflag: _toInt(json['weighflag']),
      sellclearflag: _toInt(json['sellclearflag']),
      recommendflag: _toInt(json['recommendflag']),
      stockqty: _toDouble(json['stockqty']),
      isort: _toInt(json['isort']),
      typeproisort: _toInt(json['typeproisort']),
      mprice1: _toDouble(json['mprice1']),
      mprice2: _toDouble(json['mprice2']),
      mprice3: _toDouble(json['mprice3']),
      dscflag: _toInt(json['dscflag']) == 0 ? 0 : 1,
      maxsellqty: _toDouble(json['maxsellqty']),
      printflag: _toInt(json['printflag']) == 0 ? 0 : 1,
      pointflag: _toInt(json['pointflag']),
      minsaleflag: _toInt(json['minsaleflag']) == 0 ? 0 : 1,
      presentflag: _toInt(json['presentflag']),
      stockflag: _toInt(json['stockflag']),
      inprice: _toDouble(json['inprice']),
      startsellqty: _toDouble(json['startsellqty']),
      addsellqty: _toDouble(json['addsellqty']),
      servicefeeflag: _toInt(json['servicefeeflag']),
      moreeatflag: _toInt(json['moreeatflag']),
      combtype: _toInt(json['combtype']),
      mobileshowflag: _toInt(json['mobileshowflag']) == 0 ? 0 : 1,
      datetype: _toInt(json['datetype']),
      begindate: json['begindate']?.toString() ?? '',
      enddate: json['enddate']?.toString() ?? '',
    );
  }

  final String productid;
  final String name;
  final double sellprice;
  final String typeid;
  final String typename;
  final String unit;
  final String imageurl;
  final String barcode;
  final String helpcode;

  /// 多做法标识 1是 0否
  final int cookflag;

  /// 多规格标识 1是 0否
  final int specflag;

  /// 套餐标识 1是 0否
  final int combflag;

  /// 时价菜标识 1是 0否（对齐 smdcapp curflag）
  final int curflag;

  /// 称重菜标识 1是 0否（对齐 smdcapp weighflag）
  final int weighflag;

  /// 沽清标识 1已沽清 0未沽清
  final int sellclearflag;

  /// 推荐菜标识
  final int recommendflag;

  /// 沽清库存数量
  final double stockqty;

  final int isort;
  final int typeproisort;

  /// 会员价1（对齐 smdcapp mprice1，prefetype=2时使用）
  final double mprice1;

  /// 会员价2（对齐 smdcapp mprice2，prefetype=3时使用）
  final double mprice2;

  /// 会员价3（对齐 smdcapp mprice3，prefetype=4时使用）
  final double mprice3;

  /// 是否可打折 1=可打折 0=不可打折（对齐 smdcapp dscflag）
  final int dscflag;

  /// 每单限量点几份（对齐 smdcapp maxsellqty，0表示不限）
  final double maxsellqty;

  /// 厨打标记（对齐 smdcapp printflag）：1=需要厨打 0=不厨打
  final int printflag;

  /// 积分标识（对齐 smdcapp pointflag）：1=计积分 0=不计
  final int pointflag;

  /// 计入低消标志（对齐 smdcapp minsaleflag）：1=计入 0=不计入
  final int minsaleflag;

  /// 可赠送标志（对齐 smdcapp presentflag）：1=可赠送
  final int presentflag;

  /// 库存管理标志（对齐 smdcapp stockflag）：1=管库存
  final int stockflag;

  /// 成本价（对齐 smdcapp inprice）
  final double inprice;

  /// 起售数量（对齐 smdcapp startsellqty）
  final double startsellqty;

  /// 增售卖数量（对齐 smdcapp addsellqty）
  final double addsellqty;

  /// 服务费标志（对齐 smdcapp servicefeeflag）：1=计服务费
  final int servicefeeflag;

  /// 一菜多吃标志（对齐 smdcapp moreeatflag）：1=支持
  final int moreeatflag;

  /// 套餐类型（对齐 smdcapp combtype）
  final int combtype;

  /// 移动端显示标志（对齐 smdcapp mobileshowflag）：1=显示
  final int mobileshowflag;

  /// 售卖日期类型（对齐 smdcapp datetype）：0=不限 1=指定日期
  final int datetype;

  /// 售卖开始日期（对齐 smdcapp begindate）
  final String begindate;

  /// 售卖结束日期（对齐 smdcapp enddate）
  final String enddate;

  /// 有效起售数量（对齐 smdcapp：startsellqty==0 按 1 处理）
  double get startQty => startsellqty <= 0 ? 1 : startsellqty;

  /// 有效增售数量（对齐 smdcapp：addsellqty<=0 按 1 处理）
  double get addQty => addsellqty <= 0 ? 1 : addsellqty;

  /// 是否显示“X份起售”按钮（起售数量大于1时显示）
  bool get showStartSell => startQty > 1;

  /// 是否有规格或做法（需要弹窗选择）
  bool get hasSpec => specflag == 1 || cookflag == 1;

  /// 是否时价菜（对齐 smdcapp curflag == 1）
  bool get isTimePrice => curflag == 1;

  /// 是否称重菜（对齐 smdcapp weighflag == 1）
  bool get isWeigh => weighflag == 1;

  /// 是否已售罄（对齐 smdcapp：sellclearflag==1 且 stockqty<=0）
  bool get isSoldOut => sellclearflag == 1 && stockqty <= 0;
}

/// 商品规格模型（对齐 smdcapp ProductSpec）
class DishSpec {
  DishSpec({
    required this.specid,
    required this.specname,
    required this.sellprice,
    this.mprice1 = 0,
    this.rrprice = 0,
    this.specpriceflag = 0,
    this.defsizeflag = 0,
    this.stockqty = 0,
    this.sellclearflag = 0,
    this.isCheck = false,
  });

  factory DishSpec.fromJson(Map<String, dynamic> json) {
    return DishSpec(
      specid: json['specid']?.toString() ?? '',
      specname: json['specname']?.toString() ?? '',
      sellprice: _toDouble(json['sellprice']),
      mprice1: _toDouble(json['mprice1']),
      rrprice: _toDouble(json['rrprice']),
      specpriceflag: _toInt(json['specpriceflag']),
      defsizeflag: _toInt(json['defsizeflag']),
      stockqty: _toDouble(json['stockqty']),
      sellclearflag: _toInt(json['sellclearflag']),
    );
  }

  final String specid;
  final String specname;
  final double sellprice;
  final double mprice1;

  /// 特价价格（specpriceflag!=0且!=4时为特价）
  final double rrprice;
  final int specpriceflag;

  /// 1=默认规格
  final int defsizeflag;
  final double stockqty;

  /// 是否开启沽清
  final int sellclearflag;

  /// 是否选中（UI状态）
  bool isCheck;

  /// 是否售罄
  bool get isSoldOut => sellclearflag == 1 && stockqty <= 0;

  /// 实际销售价（特价时取 rrprice）
  double get actualPrice =>
      (specpriceflag != 0 && specpriceflag != 4) ? rrprice : sellprice;
}

/// 做法模型（对齐 smdcapp ProductCook）
class DishCook {
  DishCook({
    required this.cookname,
    this.price = 0,
    this.ptype = 0,
    this.editqtyflag = 0,
    this.maximumflag = 0,
    this.maximum = 0,
    this.mandatoryflag = 0,
    this.mandatoryqty = 0,
    this.defrecommend = 0,
    this.isCheck = false,
    this.selectCookNum = 0,
  });

  factory DishCook.fromJson(Map<String, dynamic> json) {
    return DishCook(
      cookname: json['cookname']?.toString() ?? '',
      price: _toDouble(json['price']),
      ptype: _toInt(json['ptype']),
      editqtyflag: _toInt(json['editqtyflag']),
      maximumflag: _toInt(json['maximumflag']),
      maximum: _toInt(json['maximum']),
      mandatoryflag: _toInt(json['mandatoryflag']),
      mandatoryqty: _toDouble(json['mandatoryqty']),
      defrecommend: _toInt(json['defrecommend']),
    );
  }

  final String cookname;

  /// 做法加价
  final double price;

  /// 加价类型：0不加 1整份加 2数量加
  final int ptype;

  /// 1=可重复选择（显示加减号）
  final int editqtyflag;

  /// 是否开启最多可选
  final int maximumflag;
  final int maximum;

  /// 是否开启必选
  final int mandatoryflag;
  final double mandatoryqty;

  /// 1=默认推荐
  final int defrecommend;

  /// 是否选中（UI状态）
  bool isCheck;

  /// 选中数量
  int selectCookNum;
}

/// 做法分组（对齐 smdcapp SpecProductBean.CookdataBean）
class DishCookGroup {
  DishCookGroup({
    required this.groupname,
    required this.cooklist,
  });

  factory DishCookGroup.fromJson(Map<String, dynamic> json) {
    final List<DishCook> cooks = <DishCook>[];
    final dynamic list = json['cooklist'];
    if (list is List) {
      for (final dynamic e in list) {
        if (e is Map) {
          cooks.add(DishCook.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    return DishCookGroup(
      groupname: json['groupname']?.toString() ?? '',
      cooklist: cooks,
    );
  }

  final String groupname;
  final List<DishCook> cooklist;

  /// 分组标题后缀（对齐 smdcapp 弹窗逻辑：可重复/必选N项/最多可选N项）
  String get titleSuffix {
    if (cooklist.isEmpty) return '';
    final DishCook first = cooklist[0];
    final List<String> parts = <String>[];
    if (first.editqtyflag == 1) parts.add('可重复');
    if (first.mandatoryflag == 1) {
      final String qty = first.mandatoryqty == first.mandatoryqty.roundToDouble()
          ? first.mandatoryqty.toInt().toString()
          : first.mandatoryqty.toString();
      parts.add('必选$qty项');
    }
    if (first.maximumflag == 1) parts.add('最多可选${first.maximum}项');
    return parts.isEmpty ? '' : '(${parts.join(',')})';
  }
}

/// 规格做法数据（对齐 smdcapp SpecProductBean）
class DishSpecData {
  DishSpecData({
    this.specdata = const <DishSpec>[],
    this.cookdata = const <DishCookGroup>[],
    this.publiccook = const <DishCookGroup>[],
  });

  factory DishSpecData.fromJson(Map<String, dynamic> json) {
    final List<DishSpec> specs = <DishSpec>[];
    final dynamic specList = json['specdata'];
    if (specList is List) {
      for (final dynamic e in specList) {
        if (e is Map) {
          specs.add(DishSpec.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    final List<DishCookGroup> cooks = <DishCookGroup>[];
    final dynamic cookList = json['cookdata'];
    if (cookList is List) {
      for (final dynamic e in cookList) {
        if (e is Map) {
          cooks.add(DishCookGroup.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    // 全局做法（对齐 smdcapp SpecProductBean.publicCook）
    final List<DishCookGroup> publicCooks = <DishCookGroup>[];
    final dynamic publicCookList = json['publiccook'] ?? json['publicCook'];
    if (publicCookList is List) {
      for (final dynamic e in publicCookList) {
        if (e is Map) {
          publicCooks.add(DishCookGroup.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    return DishSpecData(specdata: specs, cookdata: cooks, publiccook: publicCooks);
  }

  /// 规格列表（单选）
  final List<DishSpec> specdata;

  /// 私有做法分组列表（对齐 smdcapp cookdata）
  final List<DishCookGroup> cookdata;

  /// 全局做法分组列表（对齐 smdcapp publicCook）
  final List<DishCookGroup> publiccook;
}

/// 服务员模型（对齐 smdcapp WaiterBean）
class Waiter {
  Waiter({
    required this.userid,
    required this.name,
    this.code = '',
  });

  factory Waiter.fromJson(Map<String, dynamic> json) {
    return Waiter(
      userid: json['userid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
    );
  }

  final String userid;
  final String name;
  final String code;
}

// ==================== 套餐模型（对齐 smdcapp SetMealBean / ProlistBean / ProductCombSet） ====================

/// 套餐明细商品（对齐 smdcapp ProductCombSet）
class ComboItem {
  ComboItem({
    required this.productid,
    required this.productname,
    this.price = 0,
    this.qty = 1,
    this.selectqty = 0,
    this.defflag = 0,
    this.repeatflag = 0,
    this.selecttype = 1,
    this.addprice = 0,
    this.cutprice = 0,
    this.unit = '',
    this.groupid = '',
    this.barcode = '',
    this.sellclearflag = 0,
    this.stockqty = 0,
    this.specname = '',
    this.specid = '',
    this.combsetproductid = '',
  });

  factory ComboItem.fromJson(Map<String, dynamic> json) {
    return ComboItem(
      productid: json['productid']?.toString() ?? '',
      productname: json['productname']?.toString() ?? '',
      price: _toDouble(json['price']),
      qty: _toDouble(json['qty']) == 0 ? 1 : _toDouble(json['qty']),
      selectqty: _toDouble(json['selectqty']),
      defflag: _toInt(json['defflag']),
      repeatflag: _toInt(json['repeatflag']),
      selecttype: _toInt(json['selecttype']) == 0 ? 1 : _toInt(json['selecttype']),
      addprice: _toDouble(json['addprice']),
      cutprice: _toDouble(json['cutprice']),
      unit: json['unit']?.toString() ?? '',
      groupid: json['groupid']?.toString() ?? '',
      barcode: json['barcode']?.toString() ?? '',
      sellclearflag: _toInt(json['sellclearflag']),
      stockqty: _toDouble(json['stockqty']),
      specname: json['specname']?.toString() ?? '',
      specid: json['specid']?.toString() ?? '',
      combsetproductid: json['combsetproductid']?.toString() ?? '',
    );
  }

  final String productid;
  final String productname;

  /// 商品单价
  final double price;

  /// 单次选择数量
  final double qty;

  /// 组内可选数量（N选M）
  final double selectqty;

  /// 是否默认选中 0否 1是
  final int defflag;

  /// 相同菜品可重复选择 0否 1是
  final int repeatflag;

  /// 选择类型 1=按数量 2=按项
  final int selecttype;

  /// 加价
  final double addprice;

  /// 减价
  final double cutprice;

  final String unit;
  final String groupid;
  final String barcode;

  /// 是否开启沽清
  final int sellclearflag;

  /// 沽清库存数量
  final double stockqty;

  /// 规格名称
  final String specname;

  /// 规格ID（对齐 smdcapp ProductCombSet.specid，非空时明细行上传 spec/specname）
  final String specid;

  /// 套餐明细配置ID（对齐 smdcapp ProductCombSet.combsetproductid）
  final String combsetproductid;

  // ===== UI 状态 =====

  /// 是否选中
  bool isCheck = false;

  /// 选中的数量
  double selectSetMealNum = 0;

  /// 是否售罄
  bool get isSoldOut => sellclearflag == 1 && stockqty <= 0;
}

/// 套餐分组（对齐 smdcapp ProlistBean）
class ComboGroup {
  ComboGroup({
    required this.groupid,
    required this.groupname,
    required this.selectqty,
    required this.list,
    this.repeatflag = 0,
    this.selecttype = 1,
  });

  factory ComboGroup.fromJson(Map<String, dynamic> json) {
    final List<ComboItem> items = <ComboItem>[];
    final dynamic list = json['list'];
    if (list is List) {
      for (final dynamic e in list) {
        if (e is Map) {
          items.add(ComboItem.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    return ComboGroup(
      groupid: json['groupid']?.toString() ?? '',
      groupname: json['groupname']?.toString() ?? '',
      selectqty: _toDouble(json['selectqty']),
      repeatflag: _toInt(json['repeatflag']),
      selecttype: _toInt(json['selecttype']) == 0 ? 1 : _toInt(json['selecttype']),
      list: items,
    );
  }

  final String groupid;
  final String groupname;

  /// 组内可选数量（N选M）
  final double selectqty;

  /// 相同菜品可重复选择 0否 1是
  final int repeatflag;

  /// 选择类型 1=按数量 2=按项
  final int selecttype;

  /// 组内商品列表
  final List<ComboItem> list;

  /// 组内商品总数量
  double get totalQty => list.fold(0, (double sum, ComboItem i) => sum + i.qty);

  /// 分组标题提示文本（对齐 smdcapp SetMealPopup 逻辑）
  String get hintText {
    final String selectQtyStr = _formatQty(selectqty);
    if (selecttype == 1) {
      final String total = _formatQty(totalQty);
      return repeatflag == 1 ? '($total选$selectQtyStr，单品可重复)' : '($total选$selectQtyStr)';
    } else {
      return repeatflag == 1 ? '(${list.length}选$selectQtyStr项，单品可重复)' : '(${list.length}选$selectQtyStr项)';
    }
  }
}

/// 套餐详情数据（对齐 smdcapp SetMealBean）
class ComboMealData {
  ComboMealData({
    required this.productid,
    required this.name,
    required this.sellprice,
    this.mprice1 = 0,
    this.combtype = 0,
    this.imageurl = '',
    this.prolist = const <ComboGroup>[],
  });

  factory ComboMealData.fromJson(Map<String, dynamic> json) {
    final List<ComboGroup> groups = <ComboGroup>[];
    final dynamic prolist = json['prolist'];
    if (prolist is List) {
      for (final dynamic e in prolist) {
        if (e is Map) {
          groups.add(ComboGroup.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    return ComboMealData(
      productid: json['productid']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sellprice: _toDouble(json['sellprice']),
      mprice1: _toDouble(json['mprice1']),
      combtype: _toInt(json['combtype']),
      imageurl: json['imageurl']?.toString() ?? '',
      prolist: groups,
    );
  }

  final String productid;
  final String name;

  /// 套餐销售价
  final double sellprice;

  /// 会员价
  final double mprice1;

  /// 套餐类型
  final int combtype;

  final String imageurl;

  /// 套餐分组列表
  final List<ComboGroup> prolist;
}

/// 会员模型（对齐 smdcapp MemberDetailsBean.ListBean 核心字段）
class VipMember {
  VipMember({
    required this.vipid,
    required this.vipname,
    required this.vipno,
    this.mobile = '',
    this.typename = '',
    this.typeid = '',
    this.prefetype = 0,
    this.discount = 100,
    this.nowmoney = 0,
    this.nowpoint = 0,
    this.capitalmoney = 0,
    this.givemoney = 0,
    this.favcount = '0',
    this.cardstatus = 1,
    this.validflag = 0,
    this.overflag = 0,
    this.overmoney = 0,
    this.arrearages = 0,
  });

  factory VipMember.fromJson(Map<String, dynamic> json) {
    return VipMember(
      vipid: json['vipid']?.toString() ?? '',
      vipname: json['vipname']?.toString() ?? '',
      vipno: json['vipno']?.toString() ?? '',
      mobile: json['mobile']?.toString() ?? '',
      typename: json['typename']?.toString() ?? '',
      typeid: json['typeid']?.toString() ?? '',
      prefetype: _toInt(json['prefetype']),
      discount: _toInt(json['discount']) == 0 ? 100 : _toInt(json['discount']),
      nowmoney: _toDouble(json['nowmoney']),
      nowpoint: _toDouble(json['nowpoint']),
      capitalmoney: _toDouble(json['capitalmoney']),
      givemoney: _toDouble(json['givemoney']),
      favcount: json['favcount']?.toString() ?? '0',
      cardstatus: _toInt(json['cardstatus']),
      validflag: _toInt(json['validflag']),
      overflag: _toInt(json['overflag']),
      overmoney: _toDouble(json['overmoney']),
      arrearages: _toDouble(json['arrearages']),
    );
  }

  final String vipid;
  final String vipname;
  final String vipno;
  final String mobile;
  final String typename;
  final String typeid;

  /// 会员优惠类型 0=无优惠 1=零售价折扣 2=会员价1 3=会员价2 4=会员价3
  final int prefetype;

  /// 会员折扣率（prefetype=1时使用，如 90 表示 9折）
  final int discount;

  /// 卡内余额
  final double nowmoney;

  /// 积分
  final double nowpoint;

  /// 本金余额（对齐 smdcapp capitalmoney）
  final double capitalmoney;

  /// 赠送余额（对齐 smdcapp givemoney）
  final double givemoney;

  /// 优惠券数量（对齐 smdcapp favcount）
  final String favcount;

  /// 卡状态 1=正常
  final int cardstatus;

  /// 是否过期 0=未过期 1=已过期
  final int validflag;

  /// 挂账标志（对齐 smdcapp MemberDetailsBean.overflag）：0=不支持挂账 1=支持
  final int overflag;

  /// 挂账额度（对齐 smdcapp MemberDetailsBean.overmoney）
  final double overmoney;

  /// 已欠款金额（对齐 smdcapp MemberDetailsBean.arrearages）
  final double arrearages;

  /// 可用挂账余额（对齐 smdcapp overmoney - arrearages）
  double get availableOverMoney => overmoney - arrearages;

  /// 显示描述（会员名 + 卡类型）
  String get displayText => '$vipname($typename)';
}

/// 格式化数量（整数不带小数点，对齐 smdcapp PriceUtil.formatQty）
String _formatQty(double qty) {
  return qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
}

/// 点餐数据仓库（对齐 smdcapp DishesApi + ProductModel）
class OrderRepository {
  OrderRepository._();

  // ==================== 本地缓存数据源（对齐 smdcapp 主设备模式读本地库） ====================

  /// 从本地缓存读取一级分类列表（对齐 smdcapp ProductTypeDao.queryAllLevel1）
  ///
  /// 过滤条件：level=1 && stopflag=0 && status=1 && mobileshowflag=1，按 isort 升序。
  static Future<List<DishCategory>> _fetchCategoriesFromLocal() async {
    final List<Map<String, dynamic>> rows =
        await TableDownloadManager.readTableData('t_bi_type');
    if (rows.isEmpty) {
      return <DishCategory>[];
    }
    final List<DishCategory> result = rows
        .where((Map<String, dynamic> r) =>
            _toInt(r['level']) == 1 &&
            _toInt(r['stopflag']) == 0 &&
            _toInt(r['status']) == 1 &&
            _toInt(r['mobileshowflag']) == 1)
        .map((Map<String, dynamic> r) => DishCategory.fromJson(r))
        .toList()
      ..sort((DishCategory a, DishCategory b) => a.isort.compareTo(b.isort));
    return result;
  }

  /// 读取本地商品 productid → combflag 映射（对齐 smdcapp ProductHelper.getProductMin）
  ///
  /// 已下单明细接口（尤其主设备模式）可能不返回 combflag 等商品参数
  /// （smdcapp CartGoodsModel.initOrderInfo 注释："主设备模式没有这些参数"），
  /// smdcapp 按 productid 从本地商品库回填 combflag，否则套餐主行会被误判为
  /// 明细行导致订单确认页已下单套餐不显示（对齐 smdcapp svn r132898 修复）。
  static Future<Map<String, int>> fetchLocalCombFlags() async {
    try {
      final List<Map<String, dynamic>> rows =
          await TableDownloadManager.readTableData('t_bi_product');
      final Map<String, int> map = <String, int>{};
      for (final Map<String, dynamic> r in rows) {
        final String pid = r['productid']?.toString() ?? '';
        if (pid.isNotEmpty) {
          map[pid] = _toInt(r['combflag']);
        }
      }
      return map;
    } catch (_) {
      return <String, int>{};
    }
  }

  /// 从本地缓存读取商品定价相关字段（对齐 smdcapp CartGoodsModel.initOrderInfo 回填逻辑）
  ///
  /// 主设备模式明细接口不返回 combflag/dscflag/mprice1~3 等商品参数，
  /// 需按 productid 从本地商品库回填，供会员价/折扣计算使用。
  /// 返回 productid → {combflag, dscflag, mprice1, mprice2, mprice3}。
  static Future<Map<String, Map<String, dynamic>>> fetchLocalProductPriceFields() async {
    try {
      final List<Map<String, dynamic>> rows =
          await TableDownloadManager.readTableData('t_bi_product');
      final Map<String, Map<String, dynamic>> map = <String, Map<String, dynamic>>{};
      for (final Map<String, dynamic> r in rows) {
        final String pid = r['productid']?.toString() ?? '';
        if (pid.isNotEmpty) {
          map[pid] = <String, dynamic>{
            'combflag': _toInt(r['combflag']),
            'dscflag': _toInt(r['dscflag']),
            'mprice1': _toDouble(r['mprice1']),
            'mprice2': _toDouble(r['mprice2']),
            'mprice3': _toDouble(r['mprice3']),
          };
        }
      }
      return map;
    } catch (_) {
      return <String, Map<String, dynamic>>{};
    }
  }

  /// 从本地缓存读取商品列表（对齐 smdcapp ProductHelper.getProduct + SaleTimeValidator）
  ///
  /// 过滤条件：stopflag=0 && status=1 && mobileshowflag=1 && 在售卖时间窗口内，按 typeproisort 升序。
  static Future<List<DishProduct>> _fetchProductsFromLocal() async {
    final List<Map<String, dynamic>> rows =
        await TableDownloadManager.readTableData('t_bi_product');
    if (rows.isEmpty) {
      return <DishProduct>[];
    }
    final List<DishProduct> result = rows
        .where((Map<String, dynamic> r) =>
            _toInt(r['stopflag']) == 0 &&
            _toInt(r['status']) == 1 &&
            _toInt(r['mobileshowflag']) == 1 &&
            _isProductSaleTimeValid(r))
        .map((Map<String, dynamic> r) => DishProduct.fromJson(r))
        .toList()
      ..sort((DishProduct a, DishProduct b) =>
          a.typeproisort.compareTo(b.typeproisort));
    return result;
  }

  /// 校验商品是否在售卖时间窗口内（对齐 smdcapp SaleTimeValidator.checkSaleTime）
  ///
  /// 基于商品自身字段，无联表：
  /// 1. 基础：stopflag==1 || status==0 → 不可售
  /// 2. 周期 cycletype：2=每周（saleweek 按位标识，1=周一..7=周日），3=每月（salemonth 逗号分隔日期）
  /// 3. 日期 datetype==2：当天在 begindate~enddate 之内
  /// 4. 时段 timetype==2：当前 HH:mm 命中 saletime “10:00-16:30|17:30-18:29” 任一段
  static bool _isProductSaleTimeValid(Map<String, dynamic> p) {
    // 1. 基础状态校验
    if (_toInt(p['stopflag']) == 1 || _toInt(p['status']) == 0) {
      return false;
    }
    final DateTime now = DateTime.now();

    // 2. 周期校验
    final int cycletype = _toInt(p['cycletype']);
    if (cycletype == 2) {
      // 每周：saleweek 为 7 位标识串，下标 = weekday-1（DateTime.weekday: 1=周一..7=周日）
      final String saleweek = p['saleweek']?.toString() ?? '';
      if (saleweek.isNotEmpty) {
        final int idx = now.weekday - 1;
        if (idx >= saleweek.length || saleweek[idx] != '1') {
          return false;
        }
      }
    } else if (cycletype == 3) {
      // 每月：salemonth 逗号分隔日期，如 "9,15,19"
      final String salemonth = p['salemonth']?.toString() ?? '';
      if (salemonth.isNotEmpty) {
        final int currentDay = now.day;
        final bool match = salemonth
            .split(',')
            .any((String d) => int.tryParse(d.trim()) == currentDay);
        if (!match) {
          return false;
        }
      }
    }

    // 3. 日期区间校验（datetype==2 指定日期）
    if (_toInt(p['datetype']) == 2) {
      final String begin = _datePart(p['begindate']);
      final String end = _datePart(p['enddate']);
      final String currentDay = _formatDay(now);
      if (begin.isNotEmpty && end.isNotEmpty &&
          (currentDay.compareTo(begin) < 0 || currentDay.compareTo(end) > 0)) {
        return false;
      }
    }

    // 4. 时段区间校验（timetype==2 指定时段）
    if (_toInt(p['timetype']) == 2) {
      final String saletime = p['saletime']?.toString() ?? '';
      if (saletime.isNotEmpty) {
        final int currentMinutes = now.hour * 60 + now.minute;
        final bool inRange = saletime.split('|').any((String slot) {
          final List<String> range = slot.split('-');
          if (range.length != 2) {
            return false;
          }
          final int? start = _parseHHmm(range[0]);
          final int? end = _parseHHmm(range[1]);
          if (start == null || end == null) {
            return false;
          }
          return currentMinutes >= start && currentMinutes <= end;
        });
        if (!inRange) {
          return false;
        }
      }
    }
    return true;
  }

  /// 取日期字符串的日期部分（yyyy-MM-dd），兼容空值与带时间部分的值
  static String _datePart(dynamic v) {
    final String s = v?.toString() ?? '';
    if (s.isEmpty || s == 'null') {
      return '';
    }
    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  /// 格式化日期为 yyyy-MM-dd
  static String _formatDay(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// 解析 "HH:mm" 为分钟数，失败返回 null
  static int? _parseHHmm(String s) {
    final List<String> parts = s.trim().split(':');
    if (parts.length != 2) {
      return null;
    }
    final int? h = int.tryParse(parts[0]);
    final int? m = int.tryParse(parts[1]);
    if (h == null || m == null) {
      return null;
    }
    return h * 60 + m;
  }

  /// 获取菜品分类列表（对齐 smdcapp /YttSvr/app/bi/type/getTypeListandCode）
  ///
  /// 对齐 smdcapp：分类无条件优先读本地 t_bi_type（ProductHelper.getDisType），
  /// 本地缓存为空（数据交换被取消/部分失败）时回退 getTypeList 实时接口。
  ///
  /// 返回一级分类列表（过滤停用的）
  static Future<List<DishCategory>> fetchCategories() async {
    // 优先读本地缓存（对齐 smdcapp 分类无条件读本地库）
    final List<DishCategory> local = await _fetchCategoriesFromLocal();
    if (local.isNotEmpty) {
      return local;
    }

    // 回退：getTypeList 实时接口
    final Map<String, dynamic> params = <String, dynamic>{};

    final Map<String, dynamic> resp = await requestForm(
      HttpApi.getTypeList,
      params,
      showError: false,
    );

    // 云服务响应: { retcode:0, data: { children: [...], alllist: [...] } }
    final dynamic data = resp['data'] ?? resp['Data'];
    if (data is Map) {
      final dynamic children = data['children'];
      if (children is List) {
        return children
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                DishCategory.fromJson(e.cast<String, dynamic>()))
            .where((DishCategory c) => c.stopflag == 0)
            .toList();
      }
    }
    return <DishCategory>[];
  }

  /// 获取全部商品列表（对齐 smdcapp SelectProductFragment.getData 双数据源）
  ///
  /// 数据源策略（对齐 smdcapp）：
  /// - 主设备模式（pcAlive）：优先读本地 t_bi_product 缓存（ProductHelper.getProduct），本地为空回退实时接口；
  /// - 云服务模式：走实时接口 getProductList（DishesApi，主设备无此端点）。
  ///
  /// 传 typeid='' 获取所有分类的商品，pagesize=9999 一次性加载全部。
  /// 每个商品自带 typeid 字段，前端按 typeid 分组实现分类滚动联动。
  static Future<List<DishProduct>> fetchAllProducts({
    String typeid = '',
    String areaid = '',
  }) async {
    // 对齐 smdcapp SelectProductFragment.getData：主设备模式（pcAlive）优先读本地 t_bi_product
    if (ConnectionManager.pcAlive) {
      final List<DishProduct> local = await _fetchProductsFromLocal();
      if (local.isNotEmpty) {
        return local;
      }
      // 本地缓存为空时回退实时接口
    }

    // 云服务模式 / 回退：getProductList 实时接口
    final Map<String, dynamic> params = <String, dynamic>{
      'typeid': typeid,
      'multicontent': '',
      'proandcomb': '1',
      'stopflag': '0',
      'page': '1',
      'pagesize': '9999',
      'scansearchflag': '1',
      'smdcflag': '1',
      'prosepcflag': '1',
      'recommendflag': '',
      'sellclearflag': '1',
      'mobileshowflag': '1',
      'field': 'typeproisort',
      'type': 'ASC',
      'areaid': areaid,
    };

    final Map<String, dynamic> resp = await requestForm(
      HttpApi.getProductList,
      params,
      showError: false,
    );

    // 云服务响应: { retcode:0, data: { list: [...], total, hasNextPage, ... } }
    final dynamic data = resp['data'] ?? resp['Data'];
    if (data is Map) {
      final dynamic list = data['list'];
      if (list is List) {
        return list
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                DishProduct.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    }
    return <DishProduct>[];
  }

  /// 获取商品规格和做法（对齐 smdcapp ProductModel.getProductCookSpec）
  ///
  /// 接口固定走云服务：POST /YttSvr/app/bi/product/getProductCookSpec
  static Future<DishSpecData> fetchProductCookSpec(String productid) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'productid': productid,
      'cookflag': '1',
      'specflag': '1',
      'smdcflag': '1',
      'specstopflag': '0',
      'sellclearflag': '1',
      'cookstopflag': '0',
    };

    final Map<String, dynamic> resp = await requestForm(
      HttpApi.getProductCookSpec,
      params,
      showError: false,
    );

    final dynamic data = resp['data'] ?? resp['Data'];
    if (data is Map) {
      return DishSpecData.fromJson(data.cast<String, dynamic>());
    }
    return DishSpecData();
  }

  /// 获取套餐详情（对齐 smdcapp ProductModel.getProductComb）
  ///
  /// 接口固定走云服务：POST /YttSvr/app/bi/comb/getInfo
  /// 参数：productid + sellclearflag=1
  static Future<ComboMealData?> fetchProductComb(String productid) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'productid': productid,
      'sellclearflag': '1',
    };

    final Map<String, dynamic> resp = await requestForm(
      HttpApi.getProductComb,
      params,
      showError: false,
    );

    final dynamic data = resp['data'] ?? resp['Data'];
    if (data is Map) {
      return ComboMealData.fromJson(data.cast<String, dynamic>());
    }
    return null;
  }

  /// 获取服务员列表（对齐 smdcapp TableApi.getUserList /YttSvr/app/user/getList）
  ///
  /// 参数对齐 smdcapp：is_page=1, page, pagesize, stopflag='0'（只查未停用）
  static Future<List<Waiter>> fetchWaiters({
    int page = 1,
    int pagesize = 100,
    String cond = '',
  }) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'is_page': '1',
      'page': '$page',
      'pagesize': '$pagesize',
      'type': '',
      'field': '',
      'stopflag': '0',
      'cond': cond,
    };

    final Map<String, dynamic> resp = await requestForm(
      HttpApi.getUserList,
      params,
      showError: false,
    );

    // 云服务响应: { retcode:0, data: { list: [...] } }
    final dynamic data = resp['data'] ?? resp['Data'];
    if (data is Map) {
      final dynamic list = data['list'];
      if (list is List) {
        return list
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                Waiter.fromJson(e.cast<String, dynamic>()))
            .where((Waiter w) => w.name.isNotEmpty)
            .toList();
      }
    }
    return <Waiter>[];
  }

  /// 获取全局做法（公共做法）列表
  ///
  /// 对齐 smdcapp ProductHelper.createCookGroupInfo(0, null) + ProductCookDao.queryCookAll：
  /// smdcapp 中 publicCook 是“本地临时变量”，并非 getProductCookSpec 接口返回，
  /// 而是从本地库 t_cook_group（做法组）+ t_cook_info（做法）组装（经 tabledown 同步）。
  /// Flutter 端无本地库，故直接调 tabledown 接口拉取两表后在内存中组装。
  static Future<List<DishCookGroup>> fetchPublicCooks() async {
    final List<Map<String, dynamic>> groups = await _tabledown('t_cook_group');
    final List<Map<String, dynamic>> infos = await _tabledown('t_cook_info');
    if (groups.isEmpty || infos.isEmpty) return <DishCookGroup>[];

    // 当前总部 id（全局做法为总部级：sid == spid，对齐 smdcapp queryCookAll(spid, spid)）
    String spid = '';
    try {
      final String storeStr = SpUtil.getString(Constant.store) ?? '';
      if (storeStr.isNotEmpty) {
        spid = (jsonDecode(storeStr) as Map<String, dynamic>)['spid']?.toString() ?? '';
      }
    } catch (_) {}

    // 有效做法组：status=1；优先取总部级（sid==spid），若无则兑底取全部（避免字段约定差异导致取空）
    List<Map<String, dynamic>> validGroups = groups
        .where((Map<String, dynamic> g) => _toInt(g['status']) == 1)
        .toList();
    if (spid.isNotEmpty) {
      final List<Map<String, dynamic>> hqGroups = validGroups
          .where((Map<String, dynamic> g) => (g['sid']?.toString() ?? '') == spid)
          .toList();
      if (hqGroups.isNotEmpty) validGroups = hqGroups;
    }
    // 组按 gisort 排序
    validGroups.sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
        _toInt(a['gisort']).compareTo(_toInt(b['gisort'])));

    // 有效做法：status=1 且未停用（stopflag=0）
    final List<Map<String, dynamic>> validInfos = infos
        .where((Map<String, dynamic> i) =>
            _toInt(i['status']) == 1 && _toInt(i['stopflag']) == 0)
        .toList();

    // 按组组装（对齐 smdcapp：按 groupid 分组，组内做法按 groupisort 排序）
    final List<DishCookGroup> result = <DishCookGroup>[];
    for (final Map<String, dynamic> g in validGroups) {
      final String groupid = g['groupid']?.toString() ?? '';
      final String groupSpid = g['spid']?.toString() ?? '';
      if (groupid.isEmpty) continue;
      final List<Map<String, dynamic>> matched = validInfos
          .where((Map<String, dynamic> i) =>
              (i['groupid']?.toString() ?? '') == groupid &&
              (groupSpid.isEmpty || (i['spid']?.toString() ?? '') == groupSpid))
          .toList()
        ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
            _toInt(a['groupisort']).compareTo(_toInt(b['groupisort'])));
      if (matched.isEmpty) continue;
      final int editqtyflag = _toInt(g['editqtyflag']);
      result.add(DishCookGroup(
        groupname: g['name']?.toString() ?? '',
        cooklist: matched
            .map((Map<String, dynamic> i) => DishCook(
                  cookname: i['name']?.toString() ?? '',
                  price: _toDouble(i['price']),
                  ptype: _toInt(i['ptype']),
                  editqtyflag: editqtyflag,
                ))
            .toList(),
      ));
    }
    return result;
  }

  /// 获取出品档口列表（对齐 smdcapp DishesApi.getKitchenList(2)：opertype=2 出品打印配置）
  ///
  /// 返回档口列表（dishid + name），失败静默返回空列表（临时菜弹窗默认“不打印”兑底）
  static Future<List<KitchenItem>> fetchKitchenList() async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.kitchenGetList,
        <String, dynamic>{
          'opertype': '2',
          'field': 'id',
          'type': 'asc',
          'page': '1',
          'pagesize': '200',
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          return list
              .whereType<Map<String, dynamic>>()
              .map((Map<String, dynamic> e) => KitchenItem(
                    dishid: e['dishid']?.toString() ?? '',
                    name: e['name']?.toString() ?? '',
                  ))
              .toList();
        }
      }
      return <KitchenItem>[];
    } catch (_) {
      return <KitchenItem>[];
    }
  }

  /// 生成菜品条码（对齐 smdcapp DishesApi.getBarcode：value=分类ID，type=1）
  static Future<String> fetchBarcode(String typeid) async {
    final Map<String, dynamic> resp = await requestForm(
      HttpApi.productGetBarcode,
      <String, dynamic>{'value': typeid, 'type': '1'},
      showError: false,
    );
    return resp['data']?.toString() ?? '';
  }

  /// 保存临时菜菜品资料（对齐 smdcapp DishesApi.addProduct）
  static Future<Map<String, dynamic>> addTempProduct(
      Map<String, dynamic> params) {
    return requestForm(HttpApi.productAdd, params, showError: false);
  }

  /// 下单（对齐 smdcapp OrderModel.postTableInfo）
  ///
  /// 主设备模式：对齐 smdcapp DishesHttpUtilPC.postTableInfo
  ///   参数 tablemaster = PCMasterBean JSON（含 tableMaster + detailList）
  /// 云服务模式：对齐 smdcapp DishesHttpUtil.postTableInfo
  ///   参数 master/detail/printmaster/printtype/printalltype
  ///
  /// [master] 主单JSON字符串（云服务模式使用）
  /// [detail] 明细JSON数组字符串（云服务模式使用）
  /// [printType] 打印类型（-1不打印，3出品单，15客单等，逗号分隔）
  /// [printAllType] 1=需要打印 -1=不需要
  /// [masterDevice] 是否走主设备
  /// [pcMasterJson] 主设备模式下的 PCMasterBean 完整JSON（含 tableMaster + detailList）
  static Future<Map<String, dynamic>> placeOrder({
    required String master,
    required String detail,
    String printType = '-1',
    int printAllType = -1,
    bool masterDevice = false,
    String? pcMasterJson,
  }) async {
    final String url =
        masterDevice ? HttpApi.pcUpSaleMasterTmp : HttpApi.upSaleMasterTmp;

    final Map<String, dynamic> params;
    if (masterDevice) {
      // 对齐 smdcapp: App.pcAlive → map["tablemaster"] = Gson().toJson(pcMasterBean)
      params = <String, dynamic>{
        'tablemaster': pcMasterJson ?? master,
      };
    } else {
      // 对齐 smdcapp 云服务: map["master"], map["printmaster"], map["detail"],
      //   map["printtype"], map["printalltype"]
      String printmaster = '';
      try {
        final Map<String, dynamic> m =
            jsonDecode(master) as Map<String, dynamic>;
        final Map<String, dynamic> pm = <String, dynamic>{
          'lowamt': m['lowamt'] ?? 0,
          'serviceamt': m['serviceamt'] ?? 0,
          'amt': m['amt'] ?? 0,
          'dscamt': m['dscamt'] ?? 0,
          'roundamt': m['roundamt'] ?? 0,
          'payamt': m['amt'] ?? 0,
        };
        printmaster = jsonEncode(pm);
      } catch (_) {}
      params = <String, dynamic>{
        'master': master,
        'printmaster': printmaster,
        'detail': detail,
        'printtype': printType,
        'printalltype': '$printAllType',
      };
    }

    return requestForm(
      url,
      params,
      showError: true,
      masterDevice: masterDevice,
    );
  }

  /// 保存桌台未落单菜品（对齐 smdcapp OrderModel.saveProduct → /api/Table/SaveProduct）
  ///
  /// 仅主设备模式可用，将购物车商品保存到主设备临时数据中。
  /// [masterJson] 主单JSON字符串（含 detailList）
  static Future<Map<String, dynamic>> saveProduct({
    required String masterJson,
  }) async {
    return requestForm(
      HttpApi.pcSaveProduct,
      <String, dynamic>{'tablemaster': masterJson},
      showError: true,
      masterDevice: true,
    );
  }

  /// 查询会员列表（对齐 smdcapp SettleApi /YttSvr/app/vip/getList）
  ///
  /// [cond] 搜索条件（卡号/姓名/手机号）
  /// 返回会员列表，失败时返回空列表
  static Future<List<VipMember>> fetchVipList(String cond) async {
    final Map<String, dynamic> params = <String, dynamic>{
      'cardstatus': '1',
      'cond': cond,
      'sids': '0',
    };

    final Map<String, dynamic> resp = await requestForm(
      HttpApi.getVipList,
      params,
      showError: false,
    );

    final dynamic data = resp['data'] ?? resp['Data'];
    if (data is Map) {
      final dynamic list = data['list'];
      if (list is List) {
        return list
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) =>
                VipMember.fromJson(e.cast<String, dynamic>()))
            .toList();
      }
    }
    return <VipMember>[];
  }

  /// 更新桌台会员信息（对齐 smdcapp OrderModel.updateMasterTmp）
  ///
  /// 录入会员后需同步更新桌台的 vip 信息到后端。
  /// 云服务：POST /YttSvr/app/sale/updateMasterTmp（表单参数）
  /// 主设备：POST /api/table/UpdateSaleMasterTmp（JSON body）
  static Future<Map<String, dynamic>> updateMasterTmpVip({
    required String saleid,
    required String tableid,
    required String tablecode,
    required String remark,
    required String personnum,
    required String serverid,
    required String servername,
    required String vipid,
    required String vipno,
    required String vipname,
    required String vipmobile,
    bool masterDevice = false,
    Map<String, dynamic>? tableJson,
  }) async {
    if (masterDevice) {
      // 主设备模式：对齐 smdcapp PCTableChangeVTO { masterTmpDto: tableInfo }
      final Map<String, dynamic> tmp = Map<String, dynamic>.from(
          tableJson?['tmp'] as Map<String, dynamic>? ?? <String, dynamic>{});
      // 对齐 smdcapp objectClone 逻辑：克隆 table 后同步更新 tmp 的
      // personnum/remark/serverid/servername 四个字段（修改开台信息/服务员生效）
      final int? personNum = int.tryParse(personnum);
      if (personNum != null) {
        tmp['personnum'] = personNum;
      }
      tmp['remark'] = remark;
      tmp['serverid'] = serverid;
      tmp['servername'] = servername;
      tmp['vipid'] = vipid;
      tmp['vipno'] = vipno;
      tmp['vipname'] = vipname;
      tmp['vipmobile'] = vipmobile;
      final Map<String, dynamic> masterDto =
          Map<String, dynamic>.from(tableJson ?? <String, dynamic>{});
      masterDto['tmp'] = tmp;
      final Map<String, dynamic> vto = <String, dynamic>{
        'masterTmpDto': masterDto,
      };
      return requestForm(
        HttpApi.pcUpdateMasterTmp,
        <String, dynamic>{'data': jsonEncode(vto)},
        showError: true,
        masterDevice: true,
      );
    } else {
      // 云服务模式：对齐 smdcapp DishesApi /YttSvr/app/sale/updateMasterTmp
      final Map<String, dynamic> params = <String, dynamic>{
        'saleid': saleid,
        'tableid': tableid,
        'tablecode': tablecode,
        'remark': remark,
        'personnum': personnum,
        'serverid': serverid,
        'servername': servername,
        'vipid': vipid,
        'vipno': vipno,
        'vipname': vipname,
        'vipmobile': vipmobile,
        'ywtype': '2',
      };
      return requestForm(
        HttpApi.updateMasterTmp,
        params,
        showError: true,
      );
    }
  }

  /// tabledown 表下载（对齐 smdcapp TableApi.downloadTableData）
  /// 返回指定表的行列表；失败时返回空列表（不阻断主流程）。
  static Future<List<Map<String, dynamic>>> _tabledown(String tablename) async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.tabledown,
        <String, dynamic>{
          'tablename': tablename,
          'page': '1',
          'pagesize': '5000',
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is List) {
        return data
            .whereType<Map<dynamic, dynamic>>()
            .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  /// 获取沽清列表（对齐 smdcapp DishesApi.findWarnList / getProductWarnListPC）
  ///
  /// 返回沽清商品列表，每项含 productid, productname, warnqty 等字段。
  static Future<List<Map<String, dynamic>>> fetchWarnList() async {
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      final Map<String, dynamic> resp;
      if (useMaster) {
        resp = await requestForm(
          HttpApi.pcGetProductWarnList,
          <String, dynamic>{'page': '1', 'pagesize': '1000'},
          masterDevice: true,
          showError: false,
        );
      } else {
        resp = await requestForm(
          HttpApi.findWarnList,
          <String, dynamic>{'page': '1', 'pagesize': '1000'},
          showError: false,
        );
      }
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          return list.whereType<Map<String, dynamic>>().toList();
        }
      } else if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  /// 从本地缓存获取必点菜列表（对齐 smdcapp ProductHelper.getMustProduct +
  /// MustMasterDao.queryAreaZC/queryAreaZCALL）
  ///
  /// 数据源为 tabledown 本地表：t_must_master（主表）、t_must_tablearea（区域关联）、
  /// t_must_product（方案商品）、t_bi_product / t_bi_product_spec（商品明细）。
  /// [areaid] 为空表示快餐模式无区域，查询全部（对齐 queryAreaZCALL）。
  static Future<List<Map<String, dynamic>>> fetchMustDishesFromLocal({
    String areaid = '',
  }) async {
    try {
      final List<Map<String, dynamic>> masters =
          await TableDownloadManager.readTableData('t_must_master');
      if (masters.isEmpty) {
        return <Map<String, dynamic>>[];
      }
      final List<Map<String, dynamic>> areas =
          await TableDownloadManager.readTableData('t_must_tablearea');
      final List<Map<String, dynamic>> mustProducts =
          await TableDownloadManager.readTableData('t_must_product');
      final List<Map<String, dynamic>> products =
          await TableDownloadManager.readTableData('t_bi_product');
      final List<Map<String, dynamic>> productSpecs =
          await TableDownloadManager.readTableData('t_bi_product_spec');

      // 当前门店 sid/spid（对齐 smdcapp SpUtils.getSID/getSPID）
      final List<String> sidSpid = _currentSidSpid();
      final String sid = sidSpid[0];
      final String spid = sidSpid[1];
      final int storemodel = StoreModeUtils.getCurrentStoreModel();

      // 区域索引：billid → areaid 列表（对齐 t_must_tablearea 关联）
      final Map<String, List<String>> billAreaMap = <String, List<String>>{};
      for (final Map<String, dynamic> a in areas) {
        final String billid = a['billid']?.toString() ?? '';
        final String aid = a['areaid']?.toString() ?? '';
        if (billid.isEmpty) continue;
        billAreaMap.putIfAbsent(billid, () => <String>[]).add(aid);
      }

      // 商品索引：productid → 商品行（对齐 ProductDao.queryByProductId）
      final Map<String, Map<String, dynamic>> productMap =
          <String, Map<String, dynamic>>{};
      for (final Map<String, dynamic> p in products) {
        final String pid = p['productid']?.toString() ?? '';
        if (pid.isNotEmpty) {
          productMap[pid] = p;
        }
      }

      final DateTime now = DateTime.now();
      final String today = _formatDay(now);
      final int nowMinutes = now.hour * 60 + now.minute;

      final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
      for (final Map<String, dynamic> m in masters) {
        // 门店过滤（对齐 queryAreaZC a.spid = :spid AND a.sid = :sid）
        if ((m['sid']?.toString() ?? '') != sid ||
            (m['spid']?.toString() ?? '') != spid) {
          continue;
        }
        // 模式开关：正餐 appflag=1 / 快餐 appflag1=1（对齐 getMustProduct filter）；
        // 无区域（快餐 queryAreaZCALL）时 appflag=1 或 appflag1=1 均有效
        final bool appOk = areaid.isEmpty
            ? (_toInt(m['appflag']) == 1 || _toInt(m['appflag1']) == 1)
            : (storemodel == StoreModeUtils.storeModelFast
                ? _toInt(m['appflag1']) == 1
                : _toInt(m['appflag']) == 1);
        if (!appOk) continue;
        if (_toInt(m['stopflag']) != 0) continue;
        if (_toInt(m['status']) != 1) continue;
        // 日期有效性：dateflag=1 时需在 startdate~enddate 内；
        // dateflag=0 的直接跳过（对齐 getMustProduct `dateflag == 0 → continue`）
        if (_toInt(m['dateflag']) != 1) continue;
        final String start = _datePart(m['startdate']);
        final String end = _datePart(m['enddate']);
        if (start.isNotEmpty && today.compareTo(start) < 0) continue;
        if (end.isNotEmpty && today.compareTo(end) > 0) continue;
        // 区域匹配（对齐 queryAreaZC：b.areaid = :areaid or b.areaid IS NULL）
        if (areaid.isNotEmpty) {
          final List<String>? areaIds =
              billAreaMap[m['billid']?.toString() ?? ''];
          if (areaIds != null &&
              areaIds.isNotEmpty &&
              !areaIds.contains(areaid)) {
            continue;
          }
        }
        // 时段校验：timeperiod1/2/3 依次判定，任一命中即有效（对齐 getMustProduct）
        if (!_isMustTimePeriodValid(m, nowMinutes)) continue;

        // 查询方案商品（对齐 MustProductDao.queryByBillid）并组装商品明细
        final String billid = m['billid']?.toString() ?? '';
        final List<Map<String, dynamic>> infoList = <Map<String, dynamic>>[];
        for (final Map<String, dynamic> mp in mustProducts) {
          if ((mp['billid']?.toString() ?? '') != billid) continue;
          final String pid = mp['productid']?.toString() ?? '';
          final Map<String, dynamic>? p = productMap[pid];
          // 商品不存在则跳过（对齐 smdcapp queryByProductId?.let）
          if (p == null) continue;
          final String specid = mp['specid']?.toString() ?? '';
          double sellprice = _toDouble(p['sellprice']);
          // 指定规格时用规格价覆盖（对齐 productSpecDao.queryBySpecid → p.sellprice）
          if (specid.isNotEmpty) {
            for (final Map<String, dynamic> ps in productSpecs) {
              if ((ps['productid']?.toString() ?? '') == pid &&
                  (ps['specid']?.toString() ?? '') == specid) {
                sellprice = _toDouble(ps['sellprice']);
                break;
              }
            }
          }
          infoList.add(<String, dynamic>{
            'productid': pid,
            'name': p['name']?.toString() ?? '',
            'sellprice': sellprice,
            'specid': specid,
            'specname': mp['specname']?.toString() ?? '',
            'combflag': _toInt(p['combflag']),
          });
        }
        result.add(<String, dynamic>{
          'mustrule': _toInt(m['mustrule']),
          'musttype': _toInt(m['musttype']),
          'name': m['name']?.toString() ?? '',
          'billid': billid,
          'checkflag': _toInt(m['checkflag']),
          'outcheckflag': _toInt(m['outcheckflag']),
          'mustproductlist': infoList,
        });
      }
      return result;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  /// 必点菜时段校验（对齐 smdcapp getMustProduct timeperiod1/2/3 链式判定）
  ///
  /// 时段1在当前有效(stopflag=0)时判定；时段2/3 仅在前一时段未命中(stopflag=1)时判定，
  /// 即多个时段为"或"关系：命中任一时段即有效。
  static bool _isMustTimePeriodValid(Map<String, dynamic> m, int nowMinutes) {
    int stopflag = 0;
    final List<String> keys = <String>['timeperiod1', 'timeperiod2', 'timeperiod3'];
    for (int i = 0; i < keys.length; i++) {
      final String period = m[keys[i]]?.toString() ?? '';
      if (period.isEmpty) continue;
      final bool shouldEval = (i == 0 && stopflag == 0) || (i > 0 && stopflag == 1);
      if (!shouldEval) continue;
      final List<String> range = period.split('-');
      if (range.length != 2) continue;
      final int? start = _parseHHmm(range[0]);
      final int? end = _parseHHmm(range[1]);
      if (start == null || end == null) continue;
      // 对齐 TimeUtils.timeIsInRound：命中时段 stopflag=0，否则置 1 继续看下一时段
      stopflag = (nowMinutes >= start && nowMinutes <= end) ? 0 : 1;
    }
    return stopflag == 0;
  }

  /// 当前门店 sid/spid（对齐 smdcapp SpUtils.getSID/getSPID，取自登录保存的 store）
  static List<String> _currentSidSpid() =>
      <String>[UserHelper.getSidStr(), UserHelper.getSpidStr()];

  /// 获取必点菜列表-云服务实时接口（对齐 smdcapp DishesApi.yxMust）
  ///
  /// 仅作为本地缓存为空时的回退（对齐分类/商品的本地优先策略）。
  /// [areaid] 桌台区域ID，[yxtype] 类型（默认 "1"）
  static Future<List<Map<String, dynamic>>> fetchMustDishes({
    required String areaid,
    String yxtype = '1',
  }) async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.yxMust,
        <String, dynamic>{
          'areaid': areaid,
          'yxtype': yxtype,
        },
        showError: false,
      );
      final dynamic data = resp['data'] ?? resp['Data'];
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList();
      } else if (data is Map<String, dynamic>) {
        final dynamic list = data['list'];
        if (list is List) {
          return list.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  /// 获取桌台保存的未落单菜品（对齐 smdcapp DishesHttpUtilPC.getSaveProductList）
  ///
  /// 仅主设备模式：POST /api/Table/GetSaveProductList
  /// 参数：tablemaster = MasterBean JSON（getMasterBeanPC 结构，含 tmp），unionFlag = "0"
  /// 返回 Data.detailList（DetailListBean 数组），失败静默返回空列表
  static Future<List<Map<String, dynamic>>> fetchSaveProductList({
    required String masterJson,
  }) async {
    try {
      final Map<String, dynamic> resp = await requestForm(
        HttpApi.pcGetSaveProductList,
        <String, dynamic>{
          'tablemaster': masterJson,
          'unionFlag': '0',
        },
        showError: false,
        masterDevice: true,
      );
      final dynamic data = resp['Data'] ?? resp['data'];
      if (data is Map<String, dynamic>) {
        final dynamic list = data['detailList'];
        if (list is List) {
          return list.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}
