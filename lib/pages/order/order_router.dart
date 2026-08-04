import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/order/order_confirm_page.dart';
import 'package:flutter_deer/pages/order/order_detail_page.dart';
import 'package:flutter_deer/pages/order/order_models.dart';
import 'package:flutter_deer/pages/order/order_page.dart';
import 'package:flutter_deer/pages/order/settle_page.dart';
import 'package:flutter_deer/pages/order/settle_finish_page.dart';
import 'package:flutter_deer/pages/order/zanjie_order_page.dart';
import 'package:flutter_deer/routers/i_router.dart';

/// 点餐模块路由
class OrderRouter implements IRouterProvider {
  static String orderPage = '/order';
  static String orderConfirmPage = '/order/confirm';
  static String orderDetailPage = '/order/detail';
  static String settlePage = '/order/settle';
  static String settleFinishPage = '/order/settleFinish';
  static String zanjieOrderPage = '/order/zanjie';

  /// 从路由上下文中安全读取arguments
  static Map<String, dynamic> _args(BuildContext? context) {
    final Object? raw = ModalRoute.of(context!)?.settings.arguments;
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return <String, dynamic>{};
  }

  @override
  void initRouter(FluroRouter router) {
    // 点菜页
    router.define(orderPage,
        handler: Handler(handlerFunc: (BuildContext? context, Map<String, List<String>> params) {
      final Map<String, dynamic> args = _args(context);
      return OrderPage(
        tableId: args['tableId'] as String? ?? '',
        tableName: args['tableName'] as String? ?? 'A01',
        tableCode: args['tableCode'] as String? ?? '',
        persons: args['persons'] as int? ?? 5,
        serverId: args['serverId'] as String? ?? '',
        serverName: args['serverName'] as String? ?? '',
        remark: args['remark'] as String? ?? '',
        saleid: args['saleid'] as String? ?? '',
        tableJson: args['tableJson'] as Map<String, dynamic>?,
        fastMode: args['fastMode'] as bool? ?? false,
      );
    }));

    // 订单确认页
    router.define(orderConfirmPage,
        handler: Handler(handlerFunc: (BuildContext? context, Map<String, List<String>> params) {
      final Map<String, dynamic> args = _args(context);
      return OrderConfirmPage(
        tableName: args['tableName'] as String? ?? 'A01',
        persons: args['persons'] as int? ?? 5,
        cartItems: args['cartItems'] as List<CartItem>? ?? <CartItem>[],
        tableId: args['tableId'] as String? ?? '',
        tableCode: args['tableCode'] as String? ?? '',
        saleid: args['saleid'] as String? ?? '',
        serverId: args['serverId'] as String? ?? '',
        serverName: args['serverName'] as String? ?? '',
        remark: args['remark'] as String? ?? '',
        tableJson: args['tableJson'] as Map<String, dynamic>?,
      );
    }));

    // 订单详情页（对齐 smdcapp OrderDetailActivity，接收桌台信息，自行请求订单数据）
    router.define(orderDetailPage,
        handler: Handler(handlerFunc: (BuildContext? context, Map<String, List<String>> params) {
      final Map<String, dynamic> args = _args(context);
      return OrderDetailPage(
        tableName: args['tableName'] as String? ?? '',
        persons: args['persons'] as int? ?? 0,
        tableId: args['tableId'] as String? ?? '',
        tableCode: args['tableCode'] as String? ?? '',
        saleid: args['saleid'] as String? ?? '',
        serverId: args['serverId'] as String? ?? '',
        serverName: args['serverName'] as String? ?? '',
        remark: args['remark'] as String? ?? '',
        tableJson: args['tableJson'] as Map<String, dynamic>?,
      );
    }));

    // 结账页（对齐 smdcapp SettleActivity）
    router.define(settlePage,
        handler: Handler(handlerFunc: (BuildContext? context, Map<String, List<String>> params) {
      final Map<String, dynamic> args = _args(context);
      return SettlePage(
        tableName: args['tableName'] as String? ?? '',
        persons: args['persons'] as int? ?? 0,
        tableId: args['tableId'] as String? ?? '',
        tableCode: args['tableCode'] as String? ?? '',
        saleid: args['saleid'] as String? ?? '',
        serverId: args['serverId'] as String? ?? '',
        serverName: args['serverName'] as String? ?? '',
        remark: args['remark'] as String? ?? '',
        tableJson: args['tableJson'] as Map<String, dynamic>?,
        detailList: (args['detailList'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            <Map<String, dynamic>>[],
        dishAmt: (args['dishAmt'] as num?)?.toDouble() ?? 0,
        serviceAmt: (args['serviceAmt'] as num?)?.toDouble() ?? 0,
        lowAmt: (args['lowAmt'] as num?)?.toDouble() ?? 0,
        disAmt: (args['disAmt'] as num?)?.toDouble() ?? 0,
        payAmt: (args['payAmt'] as num?)?.toDouble() ?? 0,
        memberVipid: args['memberVipid'] as String? ?? '',
        memberVipname: args['memberVipname'] as String? ?? '',
        memberVipno: args['memberVipno'] as String? ?? '',
        memberMobile: args['memberMobile'] as String? ?? '',
        memberOverflag: (args['memberOverflag'] as num?)?.toInt() ?? 0,
        memberOvermoney: (args['memberOvermoney'] as num?)?.toDouble() ?? 0,
        memberArrearages: (args['memberArrearages'] as num?)?.toDouble() ?? 0,
        memberNowmoney: (args['memberNowmoney'] as num?)?.toDouble() ?? 0,
        memberPrefetype: (args['memberPrefetype'] as num?)?.toInt() ?? 0,
      );
    }));

    // 结算完成页（对齐 smdcapp SettleFinishActivity）
    router.define(settleFinishPage,
        handler: Handler(handlerFunc: (BuildContext? context, Map<String, List<String>> params) {
      final Map<String, dynamic> args = _args(context);
      return SettleFinishPage(
        tableName: args['tableName'] as String? ?? '',
        payAmt: (args['payAmt'] as num?)?.toDouble() ?? 0,
        receivedAmt: (args['receivedAmt'] as num?)?.toDouble() ?? 0,
        changeAmt: (args['changeAmt'] as num?)?.toDouble() ?? 0,
        payName: args['payName'] as String? ?? '',
        takecode: args['takecode'] as String? ?? '',
      );
    }));

    // 暂结订单页（对齐 smdcapp ZjOrderActivity）
    router.define(zanjieOrderPage,
        handler: Handler(handlerFunc: (BuildContext? context, Map<String, List<String>> params) {
      final Map<String, dynamic> args = _args(context);
      return ZanjieOrderPage(
        saleid: args['saleid'] as String? ?? '',
      );
    }));
  }
}
