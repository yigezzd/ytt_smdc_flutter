import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_deer/components/confirm_dialog.dart';
import 'package:flutter_deer/components/cut_model_sheet.dart';
import 'package:flutter_deer/net/connection_manager.dart';
import 'package:flutter_deer/net/http_api.dart';
import 'package:flutter_deer/net/http_helper.dart';
import 'package:flutter_deer/net/mq_service.dart';
import 'package:flutter_deer/net/table_event_bus.dart';
import 'package:flutter_deer/pages/home/table/table_models.dart';
import 'package:flutter_deer/pages/home/table/table_repository.dart';
import 'package:flutter_deer/pages/home/table/widgets/connection_status_sheet.dart';
import 'package:flutter_deer/pages/home/table/widgets/master_device_check_dialog.dart';
import 'package:flutter_deer/pages/home/table/widgets/open_table_dialog.dart';
import 'package:flutter_deer/pages/home/table/widgets/status_filter_bar.dart';
import 'package:flutter_deer/pages/home/table/widgets/table_card.dart';
import 'package:flutter_deer/pages/home/table/widgets/table_operation_dialog.dart';
import 'package:flutter_deer/res/colors.dart';
import 'package:flutter_deer/routers/fluro_navigator.dart';
import 'package:flutter_deer/routers/routers.dart';
import 'package:flutter_deer/setting/setting_router.dart';
import 'package:flutter_deer/util/store_mode_utils.dart';
import 'package:flutter_deer/util/table_data_utils.dart';
import 'package:flutter_deer/util/theme_utils.dart';
import 'package:flutter_deer/util/toast_utils.dart';
import 'package:flutter_deer/widgets/state_layout.dart';

/// 桌台首页
class TablePage extends StatefulWidget {
  const TablePage({super.key});

  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage>
    with WidgetsBindingObserver {
  /// 品牌红
  static const Color _brandRed = Color(0xFFE63F31);

  /// 轮询间隔（对齐 smdcapp 桌台页定时刷新，5秒一次）
  static const Duration _pollInterval = Duration(seconds: 5);

  /// 区域列表（不含"全部"，"全部"为运行时合成项）
  List<TableArea> _rawAreas = <TableArea>[];

  /// 桌台列表（服务端按区域+状态筛选后的结果）
  List<TableInfo> _tables = <TableInfo>[];

  /// 区域下标: 0=全部, 其余对应 [_rawAreas]
  int _areaIndex = 0;

  /// 状态筛选: null=全部
  TableStatus? _statusFilter;

  /// 是否处于搜索模式（对齐 smdcapp imgSearch 点击切换 llSearch/TitleLayout 显示）
  bool _searchMode = false;

  /// 搜索关键词（对齐 smdcapp filterName，本地过滤桌台名称）
  String _searchKeyword = '';

  /// 搜索输入控制器
  final TextEditingController _searchController = TextEditingController();

  /// 主设备是否可达（驱动头部网络状态图标）
  bool _pcAlive = false;

  /// 是否正在加载
  bool _loading = false;

  /// 弹窗是否正在展示（防止重复弹出）
  bool _pcCheckDialogShowing = false;

  /// 定时轮询 Timer（对齐 smdcapp：桌台状态实时刷新，如锁台/开台等变更）
  Timer? _pollTimer;

  /// 是否有正在进行的静默刷新（防止并发请求）
  bool _silentRefreshing = false;

  /// 刷新期间收到新事件时标记，待当前刷新结束后再刷一次（对齐 smdcapp 操作后必定刷新）
  bool _pendingRefresh = false;

  /// MQ 推送订阅（对齐 smdcapp onMQEvent retcode=8 → initData）
  StreamSubscription<int>? _mqSubscription;

  /// 本地事件总线订阅（对齐 smdcapp EventBus 操作后立即刷新）
  StreamSubscription<void>? _eventSubscription;

  /// 主设备连接丢失事件订阅（对齐 smdcapp onNetModeEvent → showTipDialog）
  StreamSubscription<void>? _masterLostSubscription;

  @override
  void initState() {
    super.initState();
    // 对齐 smdcapp：默认正餐模式（SpUtils.getCurrentStoremodel 默认 STORE_MODEL_TYPE_2）
    if (StoreModeUtils.getCurrentStoreModel() != StoreModeUtils.storeModelNormal) {
      StoreModeUtils.putCurrentStoreModel(StoreModeUtils.storeModelNormal);
    }
    WidgetsBinding.instance.addObserver(this);

    // 订阅 MQ 推送（对齐 smdcapp @Subscribe onMQEvent: retcode 8/10/11 → 刷新桌台）
    _mqSubscription = MqService.instance.onTableChanged.listen((_) {
      _silentRefresh();
    });

    // 订阅本地事件总线（对齐 smdcapp EventBus: 开台/锁台/消台等操作后立即刷新）
    _eventSubscription = TableEventBus.onTableChanged.listen((_) {
      _silentRefresh();
    });

    // 订阅主设备连接丢失事件（对齐 smdcapp GlobalEventListener → NetModeEvent → showTipDialog）：
    // 运行期间主设备接口请求网络层失败时（如主设备被关机），弹出连接失败提示弹窗
    _masterLostSubscription =
        ConnectionManager.onMasterDeviceLost.listen((_) {
      if (!mounted || _pcCheckDialogShowing) {
        return;
      }
      setState(() => _pcAlive = false);
      _showMasterDeviceCheckDialog();
    });

    // 对齐 smdcapp：先探活确定连接模式，再按该模式加载数据（避免两套接口都调用）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPage();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 对齐 smdcapp onResume：回到前台立即刷新 + 恢复轮询
      _silentRefresh();
      // _startPolling(); // TODO: 暂时屏蔽定时轮询，待MQ稳定后再恢复
    } else if (state == AppLifecycleState.paused) {
      // 进入后台停止轮询，避免无意义请求
      _stopPolling();
    }
  }

  /// 页面初始化流程（对齐 smdcapp LoginActivity.checkPC → downTable → initData 的时序）
  ///
  /// 1. 先探活主设备，确定 pcAlive
  /// 2. 按最终模式加载数据（只调一套接口）
  /// 3. 探活失败则弹出提示弹窗
  Future<void> _initPage() async {
    final String localhost = ConnectionManager.getLocalhost();
    final bool hasLocalhost =
        localhost.isNotEmpty && localhost.startsWith('http');

    // 有主设备地址时先探活，确定连接模式（对齐 smdcapp checkPC 阻塞等待结果）
    if (hasLocalhost) {
      final bool alive = await checkMasterDeviceAlive();
      if (!mounted) {
        return;
      }
      setState(() => _pcAlive = alive);
    }

    // 按确定的模式加载数据（仅调用一套接口）
    _loadData();

    // 数据加载后启动定时轮询（对齐 smdcapp：桌台状态实时更新）
    // _startPolling(); // TODO: 暂时屏蔽定时轮询，待MQ稳定后再恢复

    // 连接 RabbitMQ 推送服务（对齐 smdcapp App.initMqTasks，登录成功后连接）
    MqService.instance.connect();

    // 主设备不可达时弹出提示弹窗（对齐 smdcapp NetWorkChangeDialog）
    if (hasLocalhost && !_pcAlive) {
      await _showMasterDeviceCheckDialog();
    }
  }

  /// 弹出主设备连接失败提示弹窗（对齐 smdcapp showTipDialog/NetWorkChangeDialog）
  ///
  /// 弹窗关闭后刷新连接状态（可能已切换云服务或重连成功）并按最新模式重载数据
  Future<void> _showMasterDeviceCheckDialog() async {
    if (!mounted || _pcCheckDialogShowing) {
      return;
    }
    _pcCheckDialogShowing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const MasterDeviceCheckDialog(),
    );
    _pcCheckDialogShowing = false;
    if (mounted) {
      setState(() => _pcAlive = ConnectionManager.pcAlive);
      _loadData();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _mqSubscription?.cancel();
    _eventSubscription?.cancel();
    _masterLostSubscription?.cancel();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _pcCheckDialogShowing = false;
    super.dispose();
  }

  // ==================== 定时轮询（对齐 smdcapp 桌台实时刷新） ====================

  /// 启动定时轮询
  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _silentRefresh());
  }

  /// 停止定时轮询
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// 静默刷新（不显示 loading、不弹错误提示，对齐 smdcapp 定时 updataTableInfo）
  ///
  /// 用于轮询和回到前台时的自动刷新，用户无感知地更新桌台状态
  /// （锁台、开台、清台等变更会在下一次轮询时自动反映到 UI）
  Future<void> _silentRefresh() async {
    if (!mounted) {
      return;
    }
    if (_silentRefreshing) {
      // 当前正在刷新，标记待刷新，等当前刷新结束后再刷一次
      _pendingRefresh = true;
      return;
    }
    _silentRefreshing = true;
    try {
      final bool useMaster = ConnectionManager.pcAlive;

      List<TableArea> areas = _rawAreas;
      List<TableInfo> tables = <TableInfo>[];

      try {
        areas = await TableRepository.fetchAreaList(masterDevice: useMaster);
      } catch (_) {
        // 静默失败，保留旧数据
      }

      try {
        tables = await TableRepository.fetchTableInfoList(
          // 重新读取最新连接状态：若上一次请求已将 pcAlive 翻转为 false，
          // 则本次回退云服务，避免以主设备路径请求云端地址
          masterDevice: ConnectionManager.pcAlive,
          areaid: _currentAreaid,
          tablestatus: _currentStatusCode,
        );
      } catch (_) {
        // 静默失败，保留旧数据
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _rawAreas = areas;
        _tables = tables;
        if (_areaIndex > _rawAreas.length) {
          _areaIndex = 0;
        }
      });
    } finally {
      _silentRefreshing = false;
      // 刷新期间有新事件到达，再刷一次（避免消台等操作后状态不更新）
      if (_pendingRefresh) {
        _pendingRefresh = false;
        _silentRefresh();
      }
    }
  }

  // ==================== 数据加载 ====================

  /// 当前区域筛选 id（空串=全部）
  String get _currentAreaid {
    if (_areaIndex <= 0 || _areaIndex > _rawAreas.length) {
      return '';
    }
    return _rawAreas[_areaIndex - 1].areaid;
  }

  /// 当前状态筛选码（空串=全部）
  String get _currentStatusCode => _statusFilter?.code.toString() ?? '';

  /// 加载区域列表 + 桌台列表（对齐 smdcapp updataTableInfo：同时刷新区域与桌台）
  Future<void> _loadData() async {
    final bool useMaster = ConnectionManager.pcAlive;
    if (mounted) {
      setState(() => _loading = true);
    }

    List<TableArea> areas = _rawAreas;
    List<TableInfo> tables = <TableInfo>[];

    try {
      areas = await TableRepository.fetchAreaList(masterDevice: useMaster);
    } catch (_) {
      // 区域加载失败保留旧数据，不阻断桌台加载
    }

    try {
      tables = await TableRepository.fetchTableInfoList(
        // 重新读取最新连接状态：若区域请求已将 pcAlive 翻转为 false，
        // 则本次回退云服务，避免以主设备路径请求云端地址
        masterDevice: ConnectionManager.pcAlive,
        areaid: _currentAreaid,
        tablestatus: _currentStatusCode,
      );
    } catch (_) {
      if (mounted) {
        Toast.show('获取桌台列表失败');
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _rawAreas = areas;
      _tables = tables;
      _loading = false;
      // 区域数量变化时修正下标
      if (_areaIndex > _rawAreas.length) {
        _areaIndex = 0;
      }
    });
  }

  // ==================== 统计 ====================

  /// 合成的"全部"区域（聚合所有区域的数量与状态统计，对齐 smdcapp getTotalNum/getallAreaStatus）
  TableArea get _allArea {
    int total = 0;
    final Map<int, int> counts = <int, int>{};
    for (final TableArea area in _rawAreas) {
      total += area.tabletotal;
      area.statusCounts.forEach((int status, int num) {
        counts[status] = (counts[status] ?? 0) + num;
      });
    }
    return TableArea(
      areaid: '-1',
      name: '全部',
      tabletotal: total,
      statusCounts: counts,
    );
  }

  /// 当前选中的区域（0=全部）
  TableArea get _selectedArea {
    if (_areaIndex <= 0 || _areaIndex > _rawAreas.length) {
      return _allArea;
    }
    return _rawAreas[_areaIndex - 1];
  }

  /// 区域Tab数量（取区域桌台总数，对齐 smdcapp tabletotal）
  int _areaCount(int index) {
    if (index == 0) {
      return _allArea.tabletotal;
    }
    if (index > _rawAreas.length) {
      return 0;
    }
    return _rawAreas[index - 1].tabletotal;
  }

  /// 底部状态数量（取选中区域的状态统计，对齐 smdcapp setStatusNumView）
  Map<TableStatus, int> get _statusCounts {
    final TableArea area = _selectedArea;
    return <TableStatus, int>{
      for (final TableStatus s in TableStatus.values)
        s: area.statusCounts[s.code] ?? 0,
    };
  }

  /// 底部"全部"数量
  int get _totalCount => _selectedArea.tabletotal;

  // ==================== 交互 ====================

  /// 搜索框文本变化（对齐 smdcapp etSearch.addTextChangedListener → filterName + initData）
  void _onSearchChanged(String text) {
    setState(() => _searchKeyword = text.trim());
  }

  /// 退出搜索模式（对齐 smdcapp tvReback：清空 filterName，隐藏搜索栏）
  void _exitSearchMode() {
    _searchController.clear();
    setState(() {
      _searchMode = false;
      _searchKeyword = '';
    });
  }

  /// 当前网络状态图标资源（对齐 smdcapp updateStatus：根据 netMode + pcAlive 切换图标）
  ///
  /// 主设备可达 → PC 成功图标；主设备连不上、实际走云服务 → 云服务图标
  String get _connectionIconAsset {
    if (_pcAlive) {
      // 主设备模式且已连接
      return 'assets/images/ic_pc_success.png';
    }
    // 主设备未连通，netMode 回退为云服务（对齐 smdcapp：netMode==2 → ic_yun_success）
    return 'assets/images/ic_yun_success.png';
  }

  /// 弹出连接状态弹窗（对齐 smdcapp ibConnection.onClick → ConnectionTypeDialog）
  void _showConnectionStatusSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ConnectionStatusSheet(),
    ).then((_) {
      // 弹窗关闭后刷新连接状态（检测过程中可能更新了 pcAlive）
      if (mounted) {
        setState(() => _pcAlive = ConnectionManager.pcAlive);
      }
    });
  }

  /// 弹出模式切换弹窗（对齐 smdcapp TableInfoActivity.showModel → CutModelPopup）
  void _showModeSwitchSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CutModelSheet(
        onSelected: (int mode) {
          if (mode == StoreModeUtils.storeModelNormal) {
            // 正餐模式（对齐 smdcapp onSure：putStoremodel3(TYPE_2) + toast）
            StoreModeUtils.putCurrentStoreModel(StoreModeUtils.storeModelNormal);
            Toast.show('切换正餐模式成功');
          } else if (mode == StoreModeUtils.storeModelFast) {
            // 快餐模式（对齐 smdcapp onCancel：putStoremodel3(TYPE_1) + 跳转点菜页）
            StoreModeUtils.putCurrentStoreModel(StoreModeUtils.storeModelFast);
            Toast.show('切换快餐模式成功');
            NavigatorUtils.push(
              context,
              Routes.orderPage,
              arguments: <String, dynamic>{
                'fastMode': true,
                'saleid': StoreModeUtils.generateSaleId(),
              },
            );
          }
        },
      ),
    );
  }

  /// 搜索过滤后的桌台列表（对齐 smdcapp filterName 过滤逻辑，本地按名称匹配）
  List<TableInfo> get _filteredTables {
    if (_searchKeyword.isEmpty) {
      return _tables;
    }
    return _tables
        .where((TableInfo t) =>
            t.name.toLowerCase().contains(_searchKeyword.toLowerCase()))
        .toList();
  }

  void _onAreaChanged(int index) {
    if (_areaIndex == index) {
      return;
    }
    setState(() => _areaIndex = index);
    _loadData();
  }

  void _onStatusChanged(TableStatus? status) {
    if (_statusFilter == status) {
      return;
    }
    setState(() => _statusFilter = status);
    _loadData();
  }

  void _onTableTap(TableInfo table) {
    if (table.isIdle) {
      // 空闲桌台 → 底部抽屉开台弹窗
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => OpenTableDialog(table: table),
      );
    } else if (table.isLocked) {
      // 锁台桌台 → 弹出解锁确认弹窗（对齐 smdcapp TipDialog 解锁流程）
      _showUnlockConfirmDialog(table);
    } else if (table.status == TableStatus.waitingOrder) {
      // 待下单桌台 → 弹出操作弹窗（对齐 smdcapp operateTable case "1" → OperationPopup2）
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TableOperationDialog(
          table: table,
        ),
      );
    } else if (table.status == TableStatus.waitingSettle ||
        table.status == TableStatus.preSettled) {
      // 待结算/已预结 → 进入订单详情页（对齐 smdcapp TableInfoActivity case "2"/"3" → OrderDetailActivity）
      NavigatorUtils.push(
        context,
        Routes.orderDetailPage,
        arguments: <String, dynamic>{
          'tableId': table.tableid,
          'tableName': table.name,
          'tableCode': table.code,
          'persons': table.tmp?.personnum ?? table.person,
          'serverId': table.tmp?.serverid ?? '',
          'serverName': table.tmp?.servername ?? '',
          'remark': table.tmp?.remark ?? '',
          'saleid': table.tmp?.saleid ?? '',
          'tableJson': table.toJson(),
        },
      );
    } else {
      // 其它状态（待清台）→ 直接进入点菜页
      NavigatorUtils.push(
        context,
        Routes.orderPage,
        arguments: <String, dynamic>{
          'tableId': table.tableid,
          'tableName': table.name,
          'tableCode': table.code,
          'persons': table.tmp?.personnum ?? table.person,
          'serverId': table.tmp?.serverid ?? '',
          'serverName': table.tmp?.servername ?? '',
          'remark': table.tmp?.remark ?? '',
          'saleid': table.tmp?.saleid ?? '',
          'tableJson': table.toJson(),
        },
      );
    }
  }

  /// 锁台桌台点击确认弹窗（对齐 smdcapp TipDialog：解锁会强制退出其它设备）
  Future<void> _showUnlockConfirmDialog(TableInfo table) async {
    final bool confirmed = await ConfirmDialog.show(
      context,
      content: '当前桌台正在其它设备上操作，解锁会强制退出其它桌台，可能会造成未保存数据丢失，是否继续解锁？',
    );
    if (confirmed && mounted) {
      _unlockTable(table);
    }
  }

  /// 解锁桌台（对齐 smdcapp TableDao.lockFlagTable(table, 0, 0)）
  Future<void> _unlockTable(TableInfo table) async {
    try {
      final bool useMaster = ConnectionManager.pcAlive;
      if (useMaster) {
        // 主设备模式：对齐 smdcapp DishesApi /api/table/TableLock，flag=0 解锁
        final Map<String, dynamic> tableBean = TableDataUtils.buildFullTableBean(
          rawJson: table.rawJson,
          fallback: <String, dynamic>{
            'tableid': table.tableid,
            'name': table.name,
            'code': table.code,
          },
        );
        tableBean['newtableid'] = table.tableid;
        if (tableBean['tmp'] is Map) {
          (tableBean['tmp'] as Map<String, dynamic>)['lockflag'] = 0;
        }
        final Map<String, dynamic> pcMaster = <String, dynamic>{
          'tableMasterTmpDto': tableBean,
          'flag': 0,
          'autoflag': 0,
        };
        await requestForm(
          HttpApi.pcTableLock,
          <String, dynamic>{'tablemaster': jsonEncode(pcMaster)},
          masterDevice: true,
        );
      } else {
        // 云服务模式：对齐 smdcapp /YttSvr/app/sale/lockFlagTable，lockflag=0 解锁
        await requestForm(HttpApi.lockFlagTable, <String, dynamic>{
          'tableid': table.tableid,
          'lockflag': '0',
          'autoflag': '0',
        });
      }
      if (!mounted) {
        return;
      }
      Toast.show('解台成功！');
      TableEventBus.fireTableChanged();
    } catch (_) {
      if (mounted) {
        Toast.show('解台失败，请重试！');
      }
    }
  }

  // ==================== UI ====================

  /// 顶部导航栏（对齐 smdcapp TitleLayout + llSearch 切换逻辑）
  Widget _buildHeader(BuildContext context, bool isDark) {
    return ColoredBox(
      color: isDark ? const Color(0xFF242526) : Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 46,
          child: _searchMode
              ? _buildSearchBar(isDark)
              : _buildTitleBar(isDark),
        ),
      ),
    );
  }

  /// 标题栏（正常模式：菜单 + 标题 + 搜索/模式切换图标）
  Widget _buildTitleBar(bool isDark) {
    return Stack(
      children: <Widget>[
        // 左侧: 菜单 + 品牌Logo
        Positioned(
          left: 6,
          top: 0,
          bottom: 0,
          child: Row(
            children: <Widget>[
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                iconSize: 22,
                color: isDark ? Colours.dark_text : const Color(0xFF4E5969),
                icon: const Icon(Icons.menu),
                onPressed: () => NavigatorUtils.push(context, SettingRouter.personalCenterPage),
              ),
            ],
          ),
        ),
        // 中间: 标题 + 网络状态（对齐 smdcapp ib_connection：点击弹出连接状态弹窗）
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '桌台',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colours.dark_text : Colours.text,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _showConnectionStatusSheet,
                child: Image.asset(
                  _connectionIconAsset,
                  width: 22,
                  height: 18,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
        // 右侧: 搜索图标 + 模式切换图标（对齐 smdcapp imgSearch + imgSx/data_change）
        Positioned(
          right: 6,
          top: 0,
          bottom: 0,
          child: Row(
            children: <Widget>[
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                iconSize: 22,
                color: isDark ? Colours.dark_text : const Color(0xFF4E5969),
                icon: const Icon(Icons.search),
                onPressed: () {
                  // 对齐 smdcapp imgSearch.onClick：隐藏 TitleLayout，显示 llSearch
                  setState(() => _searchMode = true);
                },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                iconSize: 22,
                color: isDark ? Colours.dark_text : const Color(0xFF4E5969),
                icon: Image.asset(
                  'assets/images/data_change.png',
                  width: 22,
                  height: 22,
                  color: isDark ? Colours.dark_text : const Color(0xFF4E5969),
                  colorBlendMode: BlendMode.srcIn,
                ),
                onPressed: _showModeSwitchSheet,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 搜索栏（对齐 smdcapp llSearch：返回 + 输入框 + 清除按钮）
  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          // 返回按钮（对齐 smdcapp tvReback）
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            iconSize: 20,
            color: isDark ? Colours.dark_text : const Color(0xFF1D2129),
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: _exitSearchMode,
          ),
          // 搜索输入框
          Expanded(
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3A3C3D) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 10),
                  Icon(Icons.search, size: 17,
                      color: isDark ? const Color(0xFF999999) : const Color(0xFF9CA3AF)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: _onSearchChanged,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : const Color(0xFF1D2129),
                      ),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '请输入桌台名称',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: isDark ? const Color(0xFF666666) : const Color(0xFF9CA3AF),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  // 清除按钮（对齐 smdcapp ivX）
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.cancel, size: 16,
                            color: isDark ? const Color(0xFF666666) : const Color(0xFFC9CDD4)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// 区域Tab栏
  Widget _buildAreaTabs(BuildContext context, bool isDark) {
    final int tabCount = _rawAreas.length + 1;

    return Container(
      color: isDark ? const Color(0xFF242526) : Colors.white,
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: tabCount,
        itemBuilder: (BuildContext context, int index) {
          final String name =
              index == 0 ? '全部' : _rawAreas[index - 1].name;
          final bool selected = _areaIndex == index;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onAreaChanged(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: selected ? 15 : 14,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      color: selected
                          ? (isDark ? Colors.white : const Color(0xFF1D2129))
                          : Colours.text_gray,
                    ),
                    child: Text('$name(${_areaCount(index)})'),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    width: selected ? 18 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: _brandRed,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 桌台网格 / 空态 / 加载态
  Widget _buildGrid(BuildContext context, bool isDark) {
    if (_loading && _tables.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    final List<TableInfo> displayTables = _filteredTables;

    if (displayTables.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          StateLayout(
            type: StateType.order,
            hintText: _searchKeyword.isEmpty ? '没有符合条件的桌台' : '未找到"$_searchKeyword"相关桌台',
          ),
        ],
      );
    }

    return _TableGrid(
      tables: displayTables,
      onTap: _onTableTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? ThemeUtils.light : ThemeUtils.dark,
      child: Scaffold(
        body: Column(
          children: <Widget>[
            _buildHeader(context, isDark),
            _buildAreaTabs(context, isDark),
            SizedBox(
              height: 0.6,
              child: ColoredBox(
                color: isDark ? Colours.dark_line : const Color(0xFFEDEDEF),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: isDark ? Colours.dark_bg_color : const Color(0xFFF2F3F5),
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  color: _brandRed,
                  child: _buildGrid(context, isDark),
                ),
              ),
            ),
            StatusFilterBar(
              activeStatus: _statusFilter,
              counts: _statusCounts,
              totalCount: _totalCount,
              onChanged: _onStatusChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// 桌台网格(带交错入场动画)
class _TableGrid extends StatefulWidget {
  const _TableGrid({
    required this.tables,
    required this.onTap,
  });

  final List<TableInfo> tables;
  final ValueChanged<TableInfo> onTap;

  @override
  State<_TableGrid> createState() => _TableGridState();
}

class _TableGridState extends State<_TableGrid>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _TableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当桌台id序列变化(切换筛选)时重放入场动画，
    // 选中/取消选中不触发，避免整屏闪烁
    if (!_sameIds(oldWidget.tables, widget.tables)) {
      _controller.forward(from: 0);
    }
  }

  bool _sameIds(List<TableInfo> a, List<TableInfo> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i].tableid != b[i].tableid) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<TableInfo> tables = widget.tables;

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.87,
      ),
      itemCount: tables.length,
      itemBuilder: (BuildContext context, int index) {
        // 交错入场: 每张卡片依次淡入上移
        final double start = (index * 0.035).clamp(0.0, 0.55);
        final Animation<double> animation = CurvedAnimation(
          parent: _controller,
          curve: Interval(start, (start + 0.45).clamp(0.0, 1.0),
              curve: Curves.easeOut),
        );
        return TableCard(
          key: ValueKey<String>(tables[index].tableid),
          table: tables[index],
          animation: animation,
          onTap: widget.onTap,
        );
      },
    );
  }
}
