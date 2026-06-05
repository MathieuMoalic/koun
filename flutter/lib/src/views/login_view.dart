import 'package:flutter/material.dart';

import '../api.dart';

class LoginView extends StatefulWidget {
  final VoidCallback onLoggedIn;

  const LoginView({super.key, required this.onLoggedIn});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final ApiClient _api = ApiClient();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.login(_passwordController.text);
      widget.onLoggedIn();
    } catch (err) {
      setState(() => _error = 'Login failed');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _editServerUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(
          controller: controller,
            decoration: const InputDecoration(hintText: 'http://localhost:8080'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) {
      await _api.setServerUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('koun', style: TextStyle(fontSize: 28)),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('Login'),
              ),
              TextButton(
                onPressed: _editServerUrl,
                child: const Text('Server URL'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
