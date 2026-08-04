import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/home/home_page.dart';
import 'package:flutter_deer/pages/home/reserve/reserve_page.dart';
import 'package:flutter_deer/pages/home/takeout/takeout_page.dart';
import 'package:flutter_deer/pages/home/webview_page.dart';
import 'package:flutter_deer/pages/login/login_router.dart';
import 'package:flutter_deer/pages/order/order_router.dart';
import 'package:flutter_deer/routers/i_router.dart';
import 'package:flutter_deer/routers/not_found_page.dart';
import 'package:flutter_deer/setting/setting_router.dart';

class Routes {
  static String home = '/home';
  static String webViewPage = '/webView';
  static String takeoutPage = '/takeout';
  static String reservePage = '/reserve';

  /// 点餐模块
  static String orderPage = OrderRouter.orderPage;
  static String orderConfirmPage = OrderRouter.orderConfirmPage;
  static String orderDetailPage = OrderRouter.orderDetailPage;
  static String settlePage = OrderRouter.settlePage;
  static String settleFinishPage = OrderRouter.settleFinishPage;
  static String zanjieOrderPage = OrderRouter.zanjieOrderPage;

  static final List<IRouterProvider> _listRouter = [];

  static final FluroRouter router = FluroRouter();

  static void initRoutes() {
    /// 指定路由跳转错误返回页
    router.notFoundHandler =
        Handler(handlerFunc: (BuildContext? context, Map<String, List<String>> params) {
      debugPrint('未找到目标页');
      return const NotFoundPage();
    });

    router.define(home,
        handler: Handler(
            handlerFunc: (BuildContext? context, Map<String, List<String>> params) =>
                const Home()));

    router.define(webViewPage, handler: Handler(handlerFunc: (_, params) {
      final String title = params['title']?.first ?? '';
      final String url = params['url']?.first ?? '';
      final String isAsset = params['isAsset']?.first ?? 'false';
      return WebViewPage(title: title, url: url, isAsset: isAsset == 'true');
    }));

    router.define(takeoutPage,
        handler: Handler(handlerFunc: (_, __) => const TakeoutPage()));

    router.define(reservePage,
        handler: Handler(handlerFunc: (_, __) => const ReservePage()));

    _listRouter.clear();

    /// 各自路由由各自模块管理，统一在此添加初始化
    _listRouter.add(LoginRouter());
    _listRouter.add(SettingRouter());
    _listRouter.add(OrderRouter());

    /// 初始化路由
    void initRouter(IRouterProvider routerProvider) {
      routerProvider.initRouter(router);
    }

    _listRouter.forEach(initRouter);
  }
}
