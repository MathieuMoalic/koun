import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

class SettingsView extends StatefulWidget {
  final ApiClient api;

  const SettingsView({super.key, required this.api});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  Algorithm? _algorithm;
  List<ReviewsPerDay> _stats = [];
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final algorithm = await widget.api.getAlgorithm();
    final stats = await widget.api.reviewsPerDay();
    setState(() {
      _algorithm = algorithm;
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _updateAlgorithm(Algorithm algorithm) async {
    await widget.api.setAlgorithm(algorithm);
    setState(() => _algorithm = algorithm);
  }

  Future<void> _syncQueue() async {
    setState(() => _message = null);
    try {
      await widget.api.flushReviewQueue();
      setState(() => _message = 'Synced offline reviews');
    } catch (err) {
      setState(() => _message = 'Sync failed');
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
          decoration: const InputDecoration(hintText: 'http://10.0.2.2:8080'),
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
      await widget.api.setServerUrl(url);
      setState(() => _message = 'Server URL updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Text('Algorithm:'),
            const SizedBox(width: 12),
            DropdownButton<Algorithm>(
              value: _algorithm,
              items: Algorithm.values
                  .map(
                    (algo) => DropdownMenuItem(
                      value: algo,
                      child: Text(algo.name.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  _updateAlgorithm(value);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: _syncQueue,
          child: const Text('Sync offline reviews'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: _editServerUrl,
          child: const Text('Server URL'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!),
        ],
        const SizedBox(height: 24),
        const Text('Reviews per day'),
        const SizedBox(height: 8),
        if (_stats.isEmpty)
          const Text('No stats yet')
        else
          ..._stats.take(14).map(
                (stat) => ListTile(
                  dense: true,
                  title: Text(stat.day),
                  trailing: Text('${stat.count}'),
                ),
              ),
      ],
    );
  }
}
