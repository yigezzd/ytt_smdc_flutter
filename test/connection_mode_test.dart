import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/dio_utils.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/pages/home/table/widgets/master_device_check_dialog.dart';
import 'package:flutter_deer/res/constant.dart';
import 'package:flutter_deer/setting/page/param_setting_page.dart';
import 'package:flutter_deer/util/params_sp_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sp_util/sp_util.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  final List<RequestOptions> requests = <RequestOptions>[];
  Map<String, dynamic> response = <String, dynamic>{};
  bool failRequest = false;

  setUpAll(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall call) async => call.method == 'getAll' ? <String, Object>{} : true,
    );
    await SpUtil.getInstance();
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    DioUtils.instance.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        if (failRequest) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ));
        } else {
          handler.resolve(Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: jsonEncode(response),
          ));
        }
      },
    ));
  });

  setUp(() async {
    await SpUtil.clear();
    ConnectionManager.beginSession();
    ConnectionManager.saveLocalhost('http://127.0.0.1:9094');
    await SpUtil.putString(Constant.store, jsonEncode(<String, String>{'id': '10', 'spid': '20'}));
    requests.clear();
    failRequest = false;
    response = <String, dynamic>{
      'Success': true,
      'Data': <String, String>{'sid': '10', 'spid': '20'},
    };
  });

  tearDownAll(() {
    DioUtils.instance.dio.interceptors.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      null,
    );
  });

  test('本地选择只在新会话生效并清除旧连接状态', () {
    ConnectionManager.pcAlive = true;
    expect(ConnectionManager.setServerType('2'), isTrue);
    expect(ConnectionManager.getServerType(), '2');
    expect(ConnectionManager.isCloudOnly, isFalse);
    expect(ConnectionManager.pcAlive, isTrue);
    ConnectionManager.beginSession();
    expect(ConnectionManager.isCloudOnly, isTrue);
    expect(ConnectionManager.masterDeviceReachable, isFalse);
    expect(ConnectionManager.getNetMode(), 2);
  });

  test('仅云服务不探测主设备且拒绝PC地址', () async {
    ConnectionManager.setServerType('2');
    ConnectionManager.beginSession();
    expect(await checkMasterDeviceAlive(), isFalse);
    expect(requests, isEmpty);
    expect(ConnectionManager.resolveBaseUrl(), HttpApi.baseUrlYtt);
    expect(() => ConnectionManager.resolveBaseUrl(masterDevice: true), throwsStateError);
  });

  test('不限模式探活核对门店并使用主设备', () async {
    expect(await checkMasterDeviceAlive(), isTrue);
    expect(ConnectionManager.pcAlive, isTrue);
    expect(requests.single.uri.path, HttpApi.pcGetHostSyncTime);
    expect((requests.single.data as Map<String, dynamic>)['data'], '');
  });

  test('仅主设备断线后不降级云服务', () async {
    ConnectionManager.setServerType('1');
    ConnectionManager.beginSession();
    expect(await checkMasterDeviceAlive(), isTrue);
    failRequest = true;
    await expectLater(
      requestForm(HttpApi.pcTableAreaList, <String, dynamic>{},
          masterDevice: true, showError: false),
      throwsA(isA<Exception>()),
    );
    expect(ConnectionManager.masterDeviceReachable, isFalse);
    expect(ConnectionManager.pcAlive, isTrue);
    expect(ConnectionManager.getNetMode(), 1);
    expect(ConnectionManager.resolveBaseUrl(masterDevice: true), 'http://127.0.0.1:9094');
    expect(requests.every((RequestOptions r) => r.uri.host == '127.0.0.1'), isTrue);
  });

  test('不限模式主设备不可达可使用云服务', () async {
    failRequest = true;
    expect(await checkMasterDeviceAlive(), isFalse);
    expect(ConnectionManager.pcAlive, isFalse);
    expect(ConnectionManager.getNetMode(), 2);
  });

  for (final Object? data in <Object?>[
    null,
    <String, String>{'sid': '99', 'spid': '20'},
    <String, String>{'sid': '10', 'spid': '99'},
    <String, String>{'sid': '10'},
  ]) {
    test('探活拒绝缺失或不匹配的门店信息 $data', () async {
      ConnectionManager.pcAlive = true;
      response['Data'] = data;
      expect(await checkMasterDeviceAlive(), isFalse);
      expect(ConnectionManager.masterDeviceReachable, isFalse);
    });
  }

  test('状态查看只检测可达性不切换连接', () async {
    expect(await checkMasterDeviceAlive(updateConnection: false), isTrue);
    expect(ConnectionManager.pcAlive, isFalse);
    ConnectionManager.pcAlive = true;
    failRequest = true;
    expect(await checkMasterDeviceAlive(updateConnection: false), isFalse);
    expect(ConnectionManager.pcAlive, isTrue);
  });

  test('缺失主设备地址不能把PC路径发到云端', () async {
    ConnectionManager.saveLocalhost('');
    ConnectionManager.setServerType('1');
    ConnectionManager.beginSession();
    expect(await checkMasterDeviceAlive(), isFalse);
    expect(requests, isEmpty);
    expect(() => ConnectionManager.resolveBaseUrl(masterDevice: true), throwsStateError);
  });

  test('后台统一控制优先于本地，调试版按原生豁免', () async {
    ConnectionManager.setServerType('1');
    await SpUtil.putString('ClientLinkModel', '1');
    await SpUtil.putString('ClientLinkModelValue', '2');
    expect(ConnectionManager.isServerTypeManaged, !kDebugMode);
    expect(ConnectionManager.getServerType(), kDebugMode ? '1' : '2');
    expect(ConnectionManager.setServerType('0'), kDebugMode);
    ConnectionManager.beginSession();
    expect(ConnectionManager.isCloudOnly, !kDebugMode);
  });

  test('新登录缺少后台参数时清理旧限制但保留本地选择', () {
    ParamsSpUtils.saveParams(<dynamic>[
      <String, String>{'code': 'ClientLinkModel', 'value': '1'},
      <String, String>{'code': 'ClientLinkModelValue', 'value': '2'},
    ]);
    ParamsSpUtils.saveParams(<dynamic>[]);
    expect(ConnectionManager.isServerTypeManaged, isFalse);
    expect(ConnectionManager.setServerType('1'), isTrue);
    expect(ConnectionManager.getServerType(), '1');
  });

  for (final double width in <double>[320, 560]) {
    testWidgets('参数页${width.toInt()}宽度可选三种模式且不立即切换', (WidgetTester tester) async {
      tester.view.physicalSize = Size(width, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const OKToast(child: MaterialApp(home: ParamSettingPage())));
      expect(find.text('服务连接方式'), findsOneWidget);
      expect(find.text('修改后重新登录生效'), findsOneWidget);
      for (final (String label, String type) in <(String, String)>[
        ('仅限云服务', '2'),
        ('仅限主设备', '1'),
        ('不限', '0'),
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
        expect(ConnectionManager.getServerType(), type);
        expect(ConnectionManager.isCloudOnly, isFalse);
        expect(ConnectionManager.isMasterOnly, isFalse);
        final ChoiceChip chip = tester.widget<ChoiceChip>(
          find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip)),
        );
        expect(chip.selected, isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('仅主设备失败弹窗不允许连接云服务或关闭', (WidgetTester tester) async {
    ConnectionManager.setServerType('1');
    ConnectionManager.beginSession();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MasterDeviceCheckDialog())));
    expect(find.text('连接云服务'), findsNothing);
    expect(find.text('重新登录'), findsOneWidget);
    expect(find.text('重连主设备'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(2));
  });

  testWidgets('不限模式手动连接云服务不覆盖参数配置', (WidgetTester tester) async {
    ConnectionManager.setServerType('1');
    await tester.pumpWidget(OKToast(
        child: MaterialApp(
            home: Builder(
      builder: (BuildContext context) => TextButton(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => const MasterDeviceCheckDialog(),
        ),
        child: const Text('打开'),
      ),
    ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接云服务'));
    await tester.pumpAndSettle();
    expect(ConnectionManager.pcAlive, isFalse);
    expect(ConnectionManager.getServerType(), '1');
    await tester.pump(const Duration(seconds: 3));
  });
}
