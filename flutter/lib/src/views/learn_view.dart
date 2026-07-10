import 'package:flutter/material.dart';

import '../api.dart';
import '../card_audio_player.dart';
import '../models.dart';

class LearnView extends StatefulWidget {
  final ApiClient api;
  final Future<void> Function()? onUnauthorized;

  const LearnView({super.key, required this.api, this.onUnauthorized});

  @override
  State<LearnView> createState() => _LearnViewState();
}

class _LearnViewState extends State<LearnView> {
  final CardAudioPlayer _audioPlayer = createCardAudioPlayer();
  NextReviewResponse? _response;
  bool _loading = true;
  bool _showBack = false;
  String? _error;
  int? _lastAutoPlayedCardId;

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
      await _playCardAudioOnce(response.next);
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
    final next = _response?.next;
    if (next == null) {
      return;
    }
    final event = ReviewEvent(
      cardDirectionId: next.cardDirectionId,
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

  Future<void> _playCardAudioOnce(ReviewItem? reviewItem) async {
    if (reviewItem == null ||
        reviewItem.direction != ReviewDirection.plToEn ||
        _lastAutoPlayedCardId == reviewItem.cardId) {
      return;
    }
    _lastAutoPlayedCardId = reviewItem.cardId;
    try {
      final bytes = await widget.api.downloadCardAudio(reviewItem.cardId);
      await _audioPlayer.playBytes(bytes, cardId: reviewItem.cardId);
    } on UnauthorizedException {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } catch (_) {
      // If autoplay fails, keep the card visible and let the user continue.
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
                      _showBack ? next.answer : next.prompt,
                      style: const TextStyle(fontSize: 22),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_showBack)
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
