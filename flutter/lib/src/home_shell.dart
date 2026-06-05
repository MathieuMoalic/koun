import 'package:flutter/material.dart';

import 'api.dart';
import 'views/add_card_view.dart';
import 'views/learn_view.dart';
import 'views/login_view.dart';
import 'views/settings_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final ApiClient _api = ApiClient();
  int _index = 0;
  bool? _loggedIn;

  Future<void> _handleUnauthorized() async {
    await _api.clearAuth();
    setState(() => _loggedIn = false);
  }

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final hasToken = await _api.hasToken();
    setState(() => _loggedIn = hasToken);
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn != true) {
      return LoginView(
        onLoggedIn: () {
          setState(() => _loggedIn = true);
        },
      );
    }

    final tabs = [
      LearnView(api: _api, onUnauthorized: _handleUnauthorized),
      AddCardView(api: _api, onUnauthorized: _handleUnauthorized),
      SettingsView(api: _api, onUnauthorized: _handleUnauthorized),
    ];

    return Scaffold(
      body: tabs[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.school), label: 'Learn'),
          NavigationDestination(icon: Icon(Icons.add), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
