import 'package:flutter/material.dart';

import '../api.dart';

class AddCardView extends StatefulWidget {
  final ApiClient api;

  const AddCardView({super.key, required this.api});

  @override
  State<AddCardView> createState() => _AddCardViewState();
}

class _AddCardViewState extends State<AddCardView> {
  final _frontController = TextEditingController();
  final _backController = TextEditingController();
  final _hintController = TextEditingController();
  bool _saving = false;
  String? _message;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.api.createCard(
        front: _frontController.text,
        back: _backController.text,
        hint: _hintController.text.isEmpty ? null : _hintController.text,
      );
      _frontController.clear();
      _backController.clear();
      _hintController.clear();
      setState(() => _message = 'Saved');
    } catch (err) {
      setState(() => _message = 'Failed to save');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            controller: _frontController,
            decoration: const InputDecoration(labelText: 'Front'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _backController,
            decoration: const InputDecoration(labelText: 'Back'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hintController,
            decoration: const InputDecoration(labelText: 'Hint (optional)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator()
                : const Text('Add card'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!),
          ],
        ],
      ),
    );
  }
}
