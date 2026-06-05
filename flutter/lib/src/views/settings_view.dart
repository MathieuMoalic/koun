import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

class SettingsView extends StatefulWidget {
  final ApiClient api;
  final Future<void> Function()? onUnauthorized;

  const SettingsView({super.key, required this.api, this.onUnauthorized});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  List<ReviewsPerDay> _stats = [];
  bool _loading = true;
  String? _message;
  final TextEditingController _retentionController = TextEditingController();
  final TextEditingController _learningStepsController = TextEditingController();
  final TextEditingController _relearningStepsController = TextEditingController();

  static const double _defaultRetention = 0.9;
  static const String _defaultLearningSteps = '1m, 10m';
  static const String _defaultRelearningSteps = '10m';

  @override
  void initState() {
    super.initState();
    _retentionController.text = _defaultRetention.toStringAsFixed(2);
    _learningStepsController.text = _defaultLearningSteps;
    _relearningStepsController.text = _defaultRelearningSteps;
    _load();
  }

  @override
  void dispose() {
    _retentionController.dispose();
    _learningStepsController.dispose();
    _relearningStepsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await widget.api.reviewsPerDay();
      final settings = await widget.api.getFsrsSettings();
      setState(() {
        _stats = stats;
        _retentionController.text =
            settings.desiredRetention.toStringAsFixed(2);
        _learningStepsController.text = settings.learningSteps.join(', ');
        _relearningStepsController.text = settings.relearningSteps.join(', ');
        _loading = false;
      });
    } on UnauthorizedException {
      setState(() {
        _message = 'Session expired. Please log in again.';
        _loading = false;
      });
      await widget.onUnauthorized?.call();
    } catch (_) {
      setState(() {
        _message = 'Failed to load settings.';
        _loading = false;
      });
    }
  }

  Future<void> _saveFsrsSettings() async {
    setState(() => _message = null);
    final retention = double.tryParse(_retentionController.text.trim());
    if (retention == null) {
      setState(() => _message = 'Invalid desired retention.');
      return;
    }
    final learningSteps = _parseSteps(_learningStepsController.text);
    final relearningSteps = _parseSteps(_relearningStepsController.text);
    if (learningSteps.isEmpty || relearningSteps.isEmpty) {
      setState(() => _message = 'Steps must not be empty.');
      return;
    }
    try {
      await widget.api.setFsrsSettings(
        FsrsSettings(
          desiredRetention: retention,
          learningSteps: learningSteps,
          relearningSteps: relearningSteps,
        ),
      );
      setState(() => _message = 'FSRS settings saved');
    } on UnauthorizedException {
      setState(() => _message = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } catch (_) {
      setState(() => _message = 'Failed to save FSRS settings.');
    }
  }

  List<String> _parseSteps(String raw) {
    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> _syncQueue() async {
    setState(() => _message = null);
    try {
      await widget.api.flushReviewQueue();
      setState(() => _message = 'Synced offline reviews');
    } on UnauthorizedException {
      setState(() => _message = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
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
        const Text(
          'FSRS Settings',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _retentionController,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Desired retention (0.90)',
            helperText: 'Typical range: 0.85–0.95',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _learningStepsController,
          decoration: const InputDecoration(
            labelText: 'Learning steps (e.g., 1m, 10m)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _relearningStepsController,
          decoration: const InputDecoration(
            labelText: 'Relearning steps (e.g., 10m)',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saveFsrsSettings,
          child: const Text('Save FSRS settings'),
        ),
        const SizedBox(height: 24),
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
