import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_deer/routers/i_router.dart';

import 'page/data_exchange_page.dart';
import 'page/login_page.dart';
import 'page/register_page.dart';
import 'page/reset_password_page.dart';
import 'page/sms_login_page.dart';
import 'page/update_password_page.dart';


class LoginRouter implements IRouterProvider{

  static String loginPage = '/login';
  static String registerPage = '/login/register';
  static String smsLoginPage = '/login/smsLogin';
  static String resetPasswordPage = '/login/resetPassword';
  static String updatePasswordPage = '/login/updatePassword';
  static String dataExchangePage = '/login/dataExchange';
  
  @override
  void initRouter(FluroRouter router) {
    router.define(loginPage, handler: Handler(handlerFunc: (_, __) => const LoginPage()));
    router.define(registerPage, handler: Handler(handlerFunc: (_, __) => const RegisterPage()));
    router.define(smsLoginPage, handler: Handler(handlerFunc: (_, __) => const SMSLoginPage()));
    router.define(resetPasswordPage, handler: Handler(handlerFunc: (_, __) => const ResetPasswordPage()));
    router.define(updatePasswordPage, handler: Handler(handlerFunc: (_, __) => const UpdatePasswordPage()));
    // 数据交换页（对齐 smdcapp ChangeDataPopup）：arguments 传 {'type': 0登录入口/1设置页入口}
    router.define(dataExchangePage, handler: Handler(handlerFunc: (BuildContext? context, __) {
      final Object? raw = ModalRoute.of(context!)?.settings.arguments;
      int type = 0;
      if (raw is Map<String, dynamic>) {
        type = raw['type'] as int? ?? 0;
      }
      return DataExchangePage(type: type);
    }));
  }
  
}
