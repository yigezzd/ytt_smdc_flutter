import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/dio_utils.dart';
import 'package:flutter_deer/net/intercept.dart';
import 'package:flutter_deer/pages/home/home_page.dart';
import 'package:flutter_deer/pages/login/page/login_page.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/routers/not_found_page.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/setting/provider/theme_provider.dart';
import 'package:flutter_deer/util/device_utils.dart';
import 'package:flutter_deer/util/file_log_writer.dart';
import 'package:flutter_deer/util/handle_error_utils.dart';
import 'package:flutter_deer/util/log_utils.dart';
import 'package:flutter_deer/util/order_log_utils.dart';
import 'package:oktoast/oktoast.dart';
import 'package:provider/provider.dart';
import 'package:sp_util/sp_util.dart';
import 'package:url_strategy/url_strategy.dart';

Future<void> main() async {
//  debugProfileBuildsEnabled = true;
//  debugPaintLayerBordersEnabled = true;
//  debugProfilePaintsEnabled = true;
//  debugRepaintRainbowEnabled = true;
  if (Constant.inProduction) {
    /// Release环境时不打印debugPrint内容
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  /// 异常处理
  handleError(() async {
    /// 确保初始化完成
    WidgetsFlutterBinding.ensureInitialized();

    /// 去除URL中的“#”(hash)，仅针对Web。默认为setHashUrlStrategy
    /// 注意本地部署和远程部署时`web/index.html`中的base标签，https://github.com/flutter/flutter/issues/69760
    setPathUrlStrategy();

    /// sp初始化
    await SpUtil.getInstance();

    /// 日志系统初始化（对齐 smdcapp JsonWriter.init + RecordsOrderLogModel）
    await FileLogWriter.instance.init();
    await OrderLogUtils.instance.init();

    /// 设备信息初始化（对齐 smdcapp DeviceUtil：供公共参数 machserial 使用）
    try {
      await Device.initDeviceInfo();
    } catch (_) {}

    /// 1.22 预览功能: 在输入频率与显示刷新率不匹配情况下提供平滑的滚动效果
    // GestureBinding.instance?.resamplingEnabled = true;
    runApp(MyApp());
  });

  /// 隐藏状态栏，导航栏。为启动页、引导页设置全屏显示。完成后还原。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  // TODO(weilu): 启动体验不佳。状态栏、导航栏在冷启动开始的一瞬间为黑色，且无法通过隐藏、修改颜色等方式进行处理。。。
  // 相关问题跟踪：https://github.com/flutter/flutter/issues/73351
}

class MyApp extends StatelessWidget {
  MyApp({super.key, this.home, this.theme}) {
    Log.init();
    initDio();
    Routes.initRoutes();
  }

  final Widget? home;
  final ThemeData? theme;
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey();

  void initDio() {
    final List<Interceptor> interceptors = <Interceptor>[];

    /// 统一添加身份验证请求头
    interceptors.add(AuthInterceptor());

    /// 刷新Token
    interceptors.add(TokenInterceptor());

    /// 打印Log(生产模式去除)
    if (!Constant.inProduction) {
      interceptors.add(LoggingInterceptor());
    }

    /// 适配数据(根据自己的数据结构，可自行选择添加)
    interceptors.add(AdapterInterceptor());
    configDio(
      baseUrl: 'https://api.github.com/',
      interceptors: interceptors,
    );
  }

  /// 根据登录状态决定启动页：未登录进登录页，已登录进首页
  Widget _getInitialPage() {
    final String token = SpUtil.getString(Constant.token) ?? '';
    return token.isNotEmpty ? const HomePage() : const LoginPage();
  }

  @override
  Widget build(BuildContext context) {
    final Widget app = MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (_, ThemeProvider provider, __) {
          return _buildMaterialApp(provider);
        },
      ),
    );

    /// Toast 配置
    return OKToast(
      backgroundColor: Colors.black54,
      textPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      radius: 20.0,
      position: ToastPosition.center,
      child: app
    );
  }

  Widget _buildMaterialApp(ThemeProvider provider) {
    return MaterialApp(
      title: '聚客美滋滋',
      // showPerformanceOverlay: true, //显示性能标签
      debugShowCheckedModeBanner: false, // 去除右上角debug的标签
      // checkerboardRasterCacheImages: true,
      // showSemanticsDebugger: true, // 显示语义视图
      // checkerboardOffscreenLayers: true, // 检查离屏渲染

      theme: theme ?? provider.getTheme(),
      darkTheme: provider.getTheme(isDarkMode: true),
      themeMode: provider.getThemeMode(),
      /// 未登录时跳转登录页，已登录进入首页
      home: home ?? _getInitialPage(),
      onGenerateRoute: Routes.router.generator,
      locale: const Locale('zh', 'CN'),
      navigatorKey: navigatorKey,
      builder: (BuildContext context, Widget? child) {
        /// 保证文字大小不受手机系统设置影响 https://www.kikt.top/posts/flutter/layout/dynamic-text/
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },

      /// 因为使用了fluro，这里设置主要针对Web
      onUnknownRoute: (_) {
        return MaterialPageRoute<void>(
          builder: (BuildContext context) => const NotFoundPage(),
        );
      },
      restorationScopeId: 'app',
    );
  }
}
