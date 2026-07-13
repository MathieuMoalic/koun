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
          'No cards due. New learned: ${_response?.newCardsLearned ?? 0}, Old reviewed: ${_response?.oldCardsReviewed ?? 0}',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text('Learned today: ${_response?.newCardsLearned ?? 0}'),
          const SizedBox(height: 8),
          Text('Reviewed today: ${_response?.oldCardsReviewed ?? 0}'),
          const SizedBox(height: 16),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showBack = !_showBack),
              child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18),
                            tooltip: 'Card actions',
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  _editCurrentCard(next);
                                  break;
                                case 'delete':
                                  _deleteCurrentCard(next);
                                  break;
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit card'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete card'),
                              ),
                            ],
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    next.cardType.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _showBack
                                    ? next.direction == ReviewDirection.plToEn
                                        ? next.cardType
                                            .formatEnglish(next.answer)
                                        : next.answer
                                    : next.direction == ReviewDirection.enToPl
                                        ? next.cardType
                                            .formatEnglish(next.prompt)
                                        : next.prompt,
                                style: const TextStyle(fontSize: 22),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Future<void> _editCurrentCard(ReviewItem next) async {
    final result = await showDialog<_LearnCardEditResult>(
      context: context,
      builder: (context) => _LearnCardEditDialog(
        cardType: next.cardType,
        front: next.direction == ReviewDirection.plToEn
            ? next.prompt
            : next.answer,
        back: next.direction == ReviewDirection.plToEn
            ? next.answer
            : next.prompt,
        hint: next.hint,
      ),
    );

    if (result == null) {
      return;
    }

    try {
      await widget.api.updateCard(
        id: next.cardId,
        front: result.front,
        back: result.back,
        cardType: result.cardType,
        hint: result.hint.isEmpty ? null : result.hint,
      );
      await _loadNext();
    } on UnauthorizedException {
      setState(() => _error = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } catch (_) {
      setState(() => _error = 'Failed to update card.');
    }
  }

  Future<void> _deleteCurrentCard(ReviewItem next) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete card?'),
        content: const Text('This will remove the card and its review history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.api.deleteCard(next.cardId);
      await _loadNext();
    } on UnauthorizedException {
      setState(() => _error = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } catch (_) {
      setState(() => _error = 'Failed to delete card.');
    }
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

class _LearnCardEditDialog extends StatefulWidget {
  final CardType cardType;
  final String front;
  final String back;
  final String? hint;

  const _LearnCardEditDialog({
    required this.cardType,
    required this.front,
    required this.back,
    required this.hint,
  });

  @override
  State<_LearnCardEditDialog> createState() => _LearnCardEditDialogState();
}

class _LearnCardEditDialogState extends State<_LearnCardEditDialog> {
  late final TextEditingController _frontController;
  late final TextEditingController _backController;
  late final TextEditingController _hintController;
  late CardType _cardType;

  @override
  void initState() {
    super.initState();
    _cardType = widget.cardType;
    _frontController = TextEditingController(text: widget.front);
    _backController = TextEditingController(text: widget.back);
    _hintController = TextEditingController(text: widget.hint ?? '');
  }

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit card'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<CardType>(
              initialValue: _cardType,
              decoration: const InputDecoration(labelText: 'Type'),
              isExpanded: true,
              items: CardType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _cardType = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _frontController,
              decoration: const InputDecoration(labelText: 'Polish'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _backController,
              decoration: InputDecoration(
                labelText: _cardType == CardType.verb ? 'English verb' : 'English',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hintController,
              decoration: const InputDecoration(labelText: 'Hint (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final front = _frontController.text.trim();
            final back = _backController.text.trim();
            final hint = _hintController.text.trim();
            if (front.isEmpty || back.isEmpty) {
              return;
            }
            Navigator.of(context).pop(
              _LearnCardEditResult(
                front: front,
                back: back,
                hint: hint,
                cardType: _cardType,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _LearnCardEditResult {
  final String front;
  final String back;
  final String hint;
  final CardType cardType;

  _LearnCardEditResult({
    required this.front,
    required this.back,
    required this.hint,
    required this.cardType,
  });
}
