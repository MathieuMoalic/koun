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
  final TextEditingController _learningStep1Controller = TextEditingController();
  final TextEditingController _learningStep2Controller = TextEditingController();
  final TextEditingController _relearningStepController = TextEditingController();

  static const double _defaultRetention = 0.9;
  static const int _defaultLearningStep1 = 1;
  static const int _defaultLearningStep2 = 10;
  static const int _defaultRelearningStep = 10;

  @override
  void initState() {
    super.initState();
    _retentionController.text = _defaultRetention.toStringAsFixed(2);
    _learningStep1Controller.text = _defaultLearningStep1.toString();
    _learningStep2Controller.text = _defaultLearningStep2.toString();
    _relearningStepController.text = _defaultRelearningStep.toString();
    _load();
  }

  @override
  void dispose() {
    _retentionController.dispose();
    _learningStep1Controller.dispose();
    _learningStep2Controller.dispose();
    _relearningStepController.dispose();
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
        _learningStep1Controller.text = settings.learningStep1Minutes.toString();
        _learningStep2Controller.text = settings.learningStep2Minutes.toString();
        _relearningStepController.text = settings.relearningStepMinutes.toString();
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
    final step1 = int.tryParse(_learningStep1Controller.text.trim());
    final step2 = int.tryParse(_learningStep2Controller.text.trim());
    final relearningStep = int.tryParse(_relearningStepController.text.trim());

    if (retention == null) {
      setState(() => _message = 'Invalid desired retention.');
      return;
    }
    if (step1 == null || step1 <= 0) {
      setState(() => _message = 'Learning step 1 must be a positive number.');
      return;
    }
    if (step2 == null || step2 <= 0) {
      setState(() => _message = 'Learning step 2 must be a positive number.');
      return;
    }
    if (relearningStep == null || relearningStep <= 0) {
      setState(() => _message = 'Relearning step must be a positive number.');
      return;
    }

    try {
      await widget.api.setFsrsSettings(
        FsrsSettings(
          desiredRetention: retention,
          learningStep1Minutes: step1,
          learningStep2Minutes: step2,
          relearningStepMinutes: relearningStep,
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
          controller: _learningStep1Controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Learning step 1 (minutes)',
            helperText: 'Minutes before repeat',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _learningStep2Controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Learning step 2 (minutes)',
            helperText: 'Minutes before graduating to long-term',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _relearningStepController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Relearning step (minutes)',
            helperText: 'Minutes when you forget a card',
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
