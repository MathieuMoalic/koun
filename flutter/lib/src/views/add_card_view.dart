import 'package:flutter/material.dart';

import '../api.dart';
import '../card_audio_player.dart';
import '../models.dart';

class AddCardView extends StatefulWidget {
  final ApiClient api;
  final Future<void> Function()? onUnauthorized;

  const AddCardView({super.key, required this.api, this.onUnauthorized});

  @override
  State<AddCardView> createState() => _AddCardViewState();
}

class _AddCardViewState extends State<AddCardView> {
  final CardAudioPlayer _audioPlayer = createCardAudioPlayer();
  final _searchController = TextEditingController();
  String? _message;
  String _query = '';
  CardSort _sort = CardSort.dueDate;
  bool _loadingCards = true;
  List<CardModel> _cards = [];

  @override
  void initState() {
    super.initState();
    _loadCards();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _playAudio(CardModel card) async {
    try {
      final bytes = await widget.api.downloadCardAudio(card.id);
      await _audioPlayer.playBytes(bytes, cardId: card.id);
    } on UnauthorizedException {
      setState(() => _message = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } on ApiException catch (error) {
      if (error.message == 'Failed to fetch card audio') {
        setState(() => _message = 'Audio not available yet');
        return;
      }
      setState(() => _message = 'Failed to play audio');
    } catch (_) {
      setState(() => _message = 'Failed to play audio');
    }
  }

  Future<void> _loadCards() async {
    setState(() => _loadingCards = true);
    try {
      final cards = await widget.api.listCards();
      setState(() => _cards = cards);
    } on UnauthorizedException {
      setState(() => _message = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } catch (_) {
      setState(() => _message = 'Failed to load cards');
    } finally {
      setState(() => _loadingCards = false);
    }
  }

  Future<void> _showAddCardModal() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _AddCardModalSheet(
        api: widget.api,
        existingCards: _cards,
        onUnauthorized: widget.onUnauthorized,
      ),
    );

    if (saved == true) {
      setState(() => _message = 'Saved');
      await _loadCards();
    }
  }

  Future<void> _editCard(CardModel card) async {
    final frontController = TextEditingController(text: card.front);
    final backController = TextEditingController(text: card.back);
    final hintController = TextEditingController(text: card.hint ?? '');
    var cardType = card.cardType;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit card'),
        content: StatefulBuilder(
          builder: (context, setModalState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: frontController,
                  decoration: const InputDecoration(labelText: 'Polish'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: backController,
                  decoration: const InputDecoration(labelText: 'English'),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hintController,
                  decoration:
                      const InputDecoration(labelText: 'Hint (optional)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CardType>(
                  initialValue: cardType,
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
                      setModalState(() => cardType = value);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true) {
      frontController.dispose();
      backController.dispose();
      hintController.dispose();
      return;
    }

    final front = frontController.text.trim();
    final back = backController.text.trim();
    final hint = hintController.text.trim();
    if (front.isEmpty || back.isEmpty) {
      setState(() => _message = 'Polish and English are required.');
      frontController.dispose();
      backController.dispose();
      hintController.dispose();
      return;
    }

    try {
      await widget.api.updateCard(
        id: card.id,
        front: front,
        back: back,
        cardType: cardType,
        hint: hint.isEmpty ? null : hint,
      );
      setState(() => _message = 'Card updated');
      await _loadCards();
    } on UnauthorizedException {
      setState(() => _message = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } catch (_) {
      setState(() => _message = 'Failed to update card');
    } finally {
      frontController.dispose();
      backController.dispose();
      hintController.dispose();
    }
  }

  Future<void> _deleteCard(CardModel card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Delete "${card.front}"?'),
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
      await widget.api.deleteCard(card.id);
      setState(() => _message = 'Card deleted');
      await _loadCards();
    } on UnauthorizedException {
      setState(() => _message = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } catch (_) {
      setState(() => _message = 'Failed to delete card');
    }
  }

  bool _fuzzyMatch(String query, String text) {
    if (query.isEmpty) {
      return true;
    }
    final q = query.toLowerCase();
    final t = text.toLowerCase();
    var qi = 0;
    for (var i = 0; i < t.length && qi < q.length; i++) {
      if (t[i] == q[qi]) {
        qi += 1;
      }
    }
    return qi == q.length;
  }

  @override
  Widget build(BuildContext context) {
    final filteredCards = _cards.where((card) {
      final haystack = [card.front, card.back, card.hint ?? ''].join(' ');
      return _fuzzyMatch(_query, haystack);
    }).toList();
    _sortCards(filteredCards);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              if (_message != null) ...[
                Text(_message!),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search cards',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Sort by'),
                  const SizedBox(width: 12),
                  DropdownButton<CardSort>(
                    value: _sort,
                    items: const [
                      DropdownMenuItem(
                        value: CardSort.dueDate,
                        child: Text('Due date'),
                      ),
                      DropdownMenuItem(
                        value: CardSort.stability,
                        child: Text('Stability'),
                      ),
                      DropdownMenuItem(
                        value: CardSort.difficulty,
                        child: Text('Difficulty'),
                      ),
                      DropdownMenuItem(
                        value: CardSort.retrievability,
                        child: Text('Retrievability'),
                      ),
                      DropdownMenuItem(
                        value: CardSort.createdAt,
                        child: Text('Created date'),
                      ),
                      DropdownMenuItem(
                        value: CardSort.updatedAt,
                        child: Text('Updated date'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sort = value);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loadingCards
                    ? const Center(child: CircularProgressIndicator())
                    : filteredCards.isEmpty
                        ? const Center(child: Text('No cards found'))
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: filteredCards.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final card = filteredCards[index];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              card.front,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          _typeBadge(card.cardType),
                                          if (card.audioAvailable)
                                            _compactIconButton(
                                              icon: Icons.play_arrow,
                                              tooltip: 'Play audio',
                                              onPressed: () => _playAudio(card),
                                            ),
                                          _compactIconButton(
                                            icon: Icons.edit,
                                            tooltip: 'Edit card',
                                            onPressed: () => _editCard(card),
                                          ),
                                          _compactIconButton(
                                            icon: Icons.delete,
                                            tooltip: 'Delete card',
                                            onPressed: () => _deleteCard(card),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        card.back,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 2,
                                        children: [
                                          _metricText(
                                            context,
                                            'D',
                                            card.fsrsDifficulty
                                                .toStringAsFixed(2),
                                          ),
                                          _metricText(
                                            context,
                                            'S',
                                            card.fsrsStability
                                                .toStringAsFixed(2),
                                          ),
                                          _metricText(
                                            context,
                                            'R',
                                            (card.fsrsRetrievability * 100)
                                                .toStringAsFixed(0),
                                            suffix: '%',
                                          ),
                                          _metricText(
                                            context,
                                            'Due',
                                            _formatRelative(card.fsrsDueAt),
                                          ),
                                        ],
                                      ),
                                      if (card.hint != null &&
                                          card.hint!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Hint: ${card.hint}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: FloatingActionButton(
              onPressed: _showAddCardModal,
              tooltip: 'Add card',
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  void _sortCards(List<CardModel> cards) {
    switch (_sort) {
      case CardSort.dueDate:
        cards.sort((a, b) => a.fsrsDueAt.compareTo(b.fsrsDueAt));
        break;
      case CardSort.stability:
        cards.sort((a, b) => b.fsrsStability.compareTo(a.fsrsStability));
        break;
      case CardSort.difficulty:
        cards.sort((a, b) => b.fsrsDifficulty.compareTo(a.fsrsDifficulty));
        break;
      case CardSort.retrievability:
        cards.sort((a, b) => b.fsrsRetrievability.compareTo(a.fsrsRetrievability));
        break;
      case CardSort.createdAt:
        cards.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case CardSort.updatedAt:
        cards.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
    }
  }

  String _formatRelative(int timestamp) {
    if (timestamp == 0) {
      return '-';
    }
    final now = DateTime.now();
    final target = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final diff = target.difference(now);
    final past = diff.isNegative;
    final seconds = diff.abs().inSeconds;

    if (seconds < 60) {
      return past ? 'just now' : 'in moments';
    }

    final minutes = seconds ~/ 60;
    if (minutes < 60) {
      return _formatUnit(minutes, 'minute', past);
    }

    final hours = minutes ~/ 60;
    if (hours < 24) {
      return _formatUnit(hours, 'hour', past);
    }

    final days = hours ~/ 24;
    if (days < 30) {
      return _formatUnit(days, 'day', past);
    }

    final months = days ~/ 30;
    if (months < 12) {
      return _formatUnit(months, 'month', past);
    }

    final years = days ~/ 365;
    return _formatUnit(years, 'year', past);
  }

  String _formatUnit(int value, String unit, bool past) {
    final label = value == 1 ? unit : '${unit}s';
    return past ? '$value $label ago' : 'in $value $label';
  }

  Widget _metricText(BuildContext context, String label, String value,
      {String suffix = ''}) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    return Text('$label $value$suffix', style: TextStyle(color: color));
  }

  Widget _compactIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      splashRadius: 16,
    );
  }

  Widget _typeBadge(CardType cardType) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          cardType.label,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

enum CardSort { dueDate, stability, difficulty, retrievability, createdAt, updatedAt }

class _AddCardModalSheet extends StatefulWidget {
  final ApiClient api;
  final List<CardModel> existingCards;
  final Future<void> Function()? onUnauthorized;

  const _AddCardModalSheet({
    required this.api,
    required this.existingCards,
    this.onUnauthorized,
  });

  @override
  State<_AddCardModalSheet> createState() => _AddCardModalSheetState();
}

class _AddCardModalSheetState extends State<_AddCardModalSheet> {
  final _frontController = TextEditingController();
  final _backController = TextEditingController();
  final _hintController = TextEditingController();
  CardType _cardType = CardType.noun;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _frontController.addListener(_onInputChanged);
    _backController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) {
      setState(() {
        if (_error == 'Duplicate card detected.') {
          _error = null;
        }
      });
    }
  }

  String _normalize(String value) => value.trim().toLowerCase();

  List<CardModel> get _frontDuplicates {
    final front = _normalize(_frontController.text);
    if (front.isEmpty) {
      return const [];
    }
    return widget.existingCards
        .where((card) => _normalize(card.front) == front)
        .toList();
  }

  List<CardModel> get _backDuplicates {
    final back = _normalize(_backController.text);
    if (back.isEmpty) {
      return const [];
    }
    return widget.existingCards
        .where((card) => _normalize(card.back) == back)
        .toList();
  }

  bool get _hasDuplicates => _frontDuplicates.isNotEmpty || _backDuplicates.isNotEmpty;

  Future<void> _save() async {
    final front = _frontController.text.trim();
    final back = _backController.text.trim();
    final hint = _hintController.text.trim();
    if (front.isEmpty || back.isEmpty) {
      setState(() => _error = 'Polish and English are required.');
      return;
    }
    if (_hasDuplicates) {
      setState(() => _error = 'Duplicate card detected.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.api.createCard(
        front: front,
        back: back,
        cardType: _cardType,
        hint: hint.isEmpty ? null : hint,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on UnauthorizedException {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Session expired. Please log in again.');
      await widget.onUnauthorized?.call();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Failed to save');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, bottomInset + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add card', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            TextField(
              controller: _frontController,
              decoration: const InputDecoration(labelText: 'Polish'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _backController,
              decoration: const InputDecoration(labelText: 'English'),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hintController,
              decoration: const InputDecoration(labelText: 'Hint (optional)'),
            ),
            const SizedBox(height: 12),
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
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _cardType = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            if (_hasDuplicates) ...[
              _DuplicateWarning(
                frontMatches: _frontDuplicates,
                backMatches: _backDuplicates,
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _saving || _hasDuplicates ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateWarning extends StatelessWidget {
  final List<CardModel> frontMatches;
  final List<CardModel> backMatches;

  const _DuplicateWarning({
    required this.frontMatches,
    required this.backMatches,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Duplicate card found',
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (frontMatches.isNotEmpty) ...[
              _DuplicateSection(
                label: 'Polish already exists',
                cards: frontMatches,
              ),
              if (backMatches.isNotEmpty) const SizedBox(height: 8),
            ],
            if (backMatches.isNotEmpty)
              _DuplicateSection(
                label: 'English already exists',
                cards: backMatches,
              ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateSection extends StatelessWidget {
  final String label;
  final List<CardModel> cards;

  const _DuplicateSection({
    required this.label,
    required this.cards,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onErrorContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        for (final card in cards)
          Text(
            '• ${card.front} → ${card.back}',
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
      ],
    );
  }
}
