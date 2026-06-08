import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

class LearnView extends StatefulWidget {
  final ApiClient api;
  final Future<void> Function()? onUnauthorized;

  const LearnView({super.key, required this.api, this.onUnauthorized});

  @override
  State<LearnView> createState() => _LearnViewState();
}

class _LearnViewState extends State<LearnView> {
  NextReviewResponse? _response;
  bool _loading = true;
  bool _showBack = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNext();
  }

  Future<void> _loadNext() async {
    setState(() => _loading = true);
    try {
      await widget.api.flushReviewQueue();
      final response = await widget.api.fetchNextReview();
      setState(() {
        _response = response;
        _showBack = false;
        _error = null;
        _loading = false;
      });
    } on UnauthorizedException {
      setState(() {
        _error = 'Session expired. Please log in again.';
        _loading = false;
      });
      await widget.onUnauthorized?.call();
    } catch (_) {
      setState(() {
        _error = 'Failed to load next review.';
        _loading = false;
      });
    }
  }

  Future<void> _submit(ReviewRating rating) async {
    final card = _response?.next?.card;
    if (card == null) {
      return;
    }
    final event = ReviewEvent(
      cardId: card.id,
      rating: rating,
      reviewedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    try {
      await widget.api.submitReview(event);
      await _loadNext();
    } on UnauthorizedException {
      setState(() => _error = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } catch (_) {
      setState(() => _error = 'Failed to submit review.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    final next = _response?.next;
    if (next == null) {
      return Center(
        child: Text(
          'No cards due. Due count: ${_response?.dueCount ?? 0}',
        ),
      );
    }

    final card = next.card;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text('Due: ${_response?.dueCount ?? 0}'),
          const SizedBox(height: 16),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showBack = !_showBack),
              child: Card(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _showBack ? card.back : card.front,
                      style: const TextStyle(fontSize: 22),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_showBack && card.hint != null) ...[
            const SizedBox(height: 8),
            Text('Hint: ${card.hint}'),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  style: _reviewButtonStyle(),
                  onPressed: () => _submit(ReviewRating.again),
                  child: const Text('Again'),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: FilledButton.tonal(
                  style: _reviewButtonStyle(),
                  onPressed: () => _submit(ReviewRating.hard),
                  child: const Text('Hard'),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: FilledButton(
                  style: _reviewButtonStyle(),
                  onPressed: () => _submit(ReviewRating.good),
                  child: const Text('Good'),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: FilledButton(
                  style: _reviewButtonStyle(),
                  onPressed: () => _submit(ReviewRating.easy),
                  child: const Text('Easy'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  ButtonStyle _reviewButtonStyle() {
    return FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}
