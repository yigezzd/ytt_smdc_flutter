import 'package:flutter/material.dart';
import 'package:flutter_deer/pages/home/table/table_page.dart';

/// 首页(桌台页)
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TablePage();
  }
}

/// 兼容旧路由引用
typedef Home = HomePage;
