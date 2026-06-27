import 'package:flutter/material.dart';

import '../api.dart';
import '../card_audio_player.dart';
import '../models.dart';

String _joinNounFront(String singular, String plural) {
  final cleanSingular = singular.trim();
  final cleanPlural = plural.trim();
  if (cleanPlural.isEmpty) {
    return cleanSingular;
  }
  return '$cleanSingular / $cleanPlural';
}

({String singular, String plural}) _splitNounFront(String value) {
  final parts = value.split(' / ');
  if (parts.length >= 2) {
    return (
      singular: parts.first.trim(),
      plural: parts.sublist(1).join(' / ').trim(),
    );
  }
  return (singular: value.trim(), plural: '');
}

String _stripEnglishDemonstrative(String value) {
  return value
      .trim()
      .replaceFirst(RegExp(r'^this\s+', caseSensitive: false), '');
}

String _joinAdjectiveFront(String masculine, String feminine, String neuter) {
  return [masculine.trim(), feminine.trim(), neuter.trim()]
      .where((part) => part.isNotEmpty)
      .join(' / ');
}

({String masculine, String feminine, String neuter}) _splitAdjectiveFront(
  String value,
) {
  final parts = value.split(RegExp(r'\s*/\s*'));
  return (
    masculine: parts.isNotEmpty ? parts[0].trim() : '',
    feminine: parts.length > 1 ? parts[1].trim() : '',
    neuter: parts.length > 2 ? parts.sublist(2).join(' / ').trim() : '',
  );
}

String _joinVerbFront(String imperfective, String perfective) {
  final cleanImperfective = imperfective.trim();
  final cleanPerfective = perfective.trim();
  if (cleanImperfective.isEmpty && cleanPerfective.isEmpty) {
    return '';
  }
  return '${cleanImperfective.isEmpty ? 'ø' : cleanImperfective} / '
      '${cleanPerfective.isEmpty ? 'ø' : cleanPerfective}';
}

({String imperfective, String perfective}) _splitVerbFront(String value) {
  final parts = value.split(RegExp(r'\s*/\s*'));
  return (
    imperfective: parts.isNotEmpty ? parts[0].trim() : '',
    perfective: parts.length > 1 ? parts.sublist(1).join(' / ').trim() : '',
  );
}

String _nounSourceText({
  required TranslationDirection direction,
  required String polishSingular,
  required String polishPlural,
  required String english,
}) {
  return switch (direction) {
    TranslationDirection.plToEn => polishSingular.trim().isNotEmpty
        ? polishSingular.trim()
        : polishPlural.trim(),
    TranslationDirection.enToPl => english.trim(),
  };
}

String _adjectiveSourceText({
  required TranslationDirection direction,
  required String polishMasculine,
  required String polishFeminine,
  required String polishNeuter,
  required String english,
}) {
  return switch (direction) {
    TranslationDirection.plToEn => [
        polishMasculine.trim(),
        polishFeminine.trim(),
        polishNeuter.trim(),
      ].firstWhere((part) => part.isNotEmpty, orElse: () => ''),
    TranslationDirection.enToPl => english.trim(),
  };
}

String _verbSourceText({
  required TranslationDirection direction,
  required String polishImperfective,
  required String polishPerfective,
  required String english,
}) {
  return switch (direction) {
    TranslationDirection.plToEn => [
        polishImperfective.trim(),
        polishPerfective.trim(),
      ].firstWhere(
        (part) => part.isNotEmpty && part != 'ø',
        orElse: () => '',
      ),
    TranslationDirection.enToPl => english.trim(),
  };
}

void _applyNounTranslation({
  required NounTranslation translation,
  required TextEditingController polishSingularController,
  required TextEditingController polishPluralController,
  required TextEditingController englishController,
}) {
  if (translation.polishSingular.isNotEmpty) {
    polishSingularController.text = translation.polishSingular;
  }
  if (translation.polishPlural.isNotEmpty) {
    polishPluralController.text = translation.polishPlural;
  }
  if (translation.english.isNotEmpty) {
    englishController.text = _stripEnglishDemonstrative(translation.english);
  }
}

void _applyVerbTranslation({
  required VerbTranslation translation,
  required TextEditingController polishImperfectiveController,
  required TextEditingController polishPerfectiveController,
  required TextEditingController englishController,
}) {
  if (translation.polishImperfective.isNotEmpty) {
    polishImperfectiveController.text = translation.polishImperfective;
  }
  if (translation.polishPerfective.isNotEmpty) {
    polishPerfectiveController.text = translation.polishPerfective;
  }
  if (translation.english.isNotEmpty) {
    englishController.text = translation.english.trim();
  }
}

void _applyAdjectiveTranslation({
  required AdjectiveTranslation translation,
  required TextEditingController polishMasculineController,
  required TextEditingController polishFeminineController,
  required TextEditingController polishNeuterController,
  required TextEditingController englishController,
}) {
  if (translation.polishMasculine.isNotEmpty) {
    polishMasculineController.text = translation.polishMasculine;
  }
  if (translation.polishFeminine.isNotEmpty) {
    polishFeminineController.text = translation.polishFeminine;
  }
  if (translation.polishNeuter.isNotEmpty) {
    polishNeuterController.text = translation.polishNeuter;
  }
  if (translation.english.isNotEmpty) {
    englishController.text = _stripEnglishDemonstrative(translation.english);
  }
}

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
    final cardType = await showModalBottomSheet<CardType>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Choose card type', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 12),
              for (final type in CardType.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(type),
                    child: Text(type.label),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (cardType == null || !mounted) {
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _AddCardModalSheet(
        api: widget.api,
        existingCards: _cards,
        initialCardType: cardType,
        onUnauthorized: widget.onUnauthorized,
      ),
    );

    if (saved == true) {
      setState(() => _message = 'Saved');
      await _loadCards();
    }
  }

  Future<void> _editCard(CardModel card) async {
    final result = await showDialog<_EditCardResult>(
      context: context,
      builder: (context) => _EditCardDialog(
        api: widget.api,
        card: card,
        onUnauthorized: widget.onUnauthorized,
      ),
    );

    if (result == null || !result.shouldSave) {
      return;
    }

    final front = result.front;
    final back = result.back;
    final hint = result.hint;
    final cardType = result.cardType;

    if (front.isEmpty || back.isEmpty) {
      setState(() => _message = 'Polish and English are required.');
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
        cards.sort(
            (a, b) => b.fsrsRetrievability.compareTo(a.fsrsRetrievability));
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
    final color =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
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

enum CardSort {
  dueDate,
  stability,
  difficulty,
  retrievability,
  createdAt,
  updatedAt
}

class _AddCardModalSheet extends StatefulWidget {
  final ApiClient api;
  final List<CardModel> existingCards;
  final CardType initialCardType;
  final Future<void> Function()? onUnauthorized;

  const _AddCardModalSheet({
    required this.api,
    required this.existingCards,
    required this.initialCardType,
    this.onUnauthorized,
  });

  @override
  State<_AddCardModalSheet> createState() => _AddCardModalSheetState();
}

class _AddCardModalSheetState extends State<_AddCardModalSheet> {
  final _frontController = TextEditingController();
  final _backController = TextEditingController();
  final _hintController = TextEditingController();
  final _nounPolishSingularController = TextEditingController();
  final _nounPolishPluralController = TextEditingController();
  final _nounEnglishController = TextEditingController();
  final _adjectivePolishMasculineController = TextEditingController();
  final _adjectivePolishFeminineController = TextEditingController();
  final _adjectivePolishNeuterController = TextEditingController();
  final _adjectiveEnglishController = TextEditingController();
  final _verbPolishImperfectiveController = TextEditingController();
  final _verbPolishPerfectiveController = TextEditingController();
  final _verbEnglishController = TextEditingController();
  late CardType _cardType;
  bool _saving = false;
  bool _translatingToEnglish = false;
  bool _translatingToPolish = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cardType = widget.initialCardType;
    _frontController.addListener(_onInputChanged);
    _backController.addListener(_onInputChanged);
    _nounPolishSingularController.addListener(_onInputChanged);
    _nounPolishPluralController.addListener(_onInputChanged);
    _nounEnglishController.addListener(_onInputChanged);
    _adjectivePolishMasculineController.addListener(_onInputChanged);
    _adjectivePolishFeminineController.addListener(_onInputChanged);
    _adjectivePolishNeuterController.addListener(_onInputChanged);
    _adjectiveEnglishController.addListener(_onInputChanged);
    _verbPolishImperfectiveController.addListener(_onInputChanged);
    _verbPolishPerfectiveController.addListener(_onInputChanged);
    _verbEnglishController.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    _hintController.dispose();
    _nounPolishSingularController.dispose();
    _nounPolishPluralController.dispose();
    _nounEnglishController.dispose();
    _adjectivePolishMasculineController.dispose();
    _adjectivePolishFeminineController.dispose();
    _adjectivePolishNeuterController.dispose();
    _adjectiveEnglishController.dispose();
    _verbPolishImperfectiveController.dispose();
    _verbPolishPerfectiveController.dispose();
    _verbEnglishController.dispose();
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
    final front = _normalize(_frontValue);
    if (front.isEmpty) {
      return const [];
    }
    return widget.existingCards
        .where((card) => _normalize(card.front) == front)
        .toList();
  }

  List<CardModel> get _backDuplicates {
    final back = _normalize(_backValue);
    if (back.isEmpty) {
      return const [];
    }
    return widget.existingCards
        .where((card) => _normalize(card.back) == back)
        .toList();
  }

  bool get _hasDuplicates =>
      _frontDuplicates.isNotEmpty || _backDuplicates.isNotEmpty;

  bool get _isNoun => _cardType == CardType.noun;
  bool get _isAdjective => _cardType == CardType.adjective;
  bool get _isVerb => _cardType == CardType.verb;

  String _joinNounFront(String singular, String plural) {
    final cleanSingular = singular.trim();
    final cleanPlural = plural.trim();
    if (cleanPlural.isEmpty) {
      return cleanSingular;
    }
    return '$cleanSingular / $cleanPlural';
  }

  String get _frontValue => _isNoun
      ? _joinNounFront(
          _nounPolishSingularController.text,
          _nounPolishPluralController.text,
        )
      : _isAdjective
          ? _joinAdjectiveFront(
              _adjectivePolishMasculineController.text,
              _adjectivePolishFeminineController.text,
              _adjectivePolishNeuterController.text,
            )
          : _isVerb
              ? _joinVerbFront(
                  _verbPolishImperfectiveController.text,
                  _verbPolishPerfectiveController.text,
                )
              : _frontController.text.trim();

  String get _backValue => _isNoun
      ? _nounEnglishController.text.trim()
      : _isAdjective
          ? _adjectiveEnglishController.text.trim()
          : _isVerb
              ? _verbEnglishController.text.trim()
              : _backController.text.trim();

  Future<void> _translate({
    required TranslationDirection direction,
  }) async {
    if (_saving) {
      return;
    }

    final sourceText = switch (direction) {
      TranslationDirection.plToEn => _isNoun
          ? _nounSourceText(
              direction: direction,
              polishSingular: _nounPolishSingularController.text,
              polishPlural: _nounPolishPluralController.text,
              english: _nounEnglishController.text,
            )
          : _isAdjective
              ? _adjectiveSourceText(
                  direction: direction,
                  polishMasculine: _adjectivePolishMasculineController.text,
                  polishFeminine: _adjectivePolishFeminineController.text,
                  polishNeuter: _adjectivePolishNeuterController.text,
                  english: _adjectiveEnglishController.text,
                )
              : _isVerb
                  ? _verbSourceText(
                      direction: direction,
                      polishImperfective:
                          _verbPolishImperfectiveController.text,
                      polishPerfective: _verbPolishPerfectiveController.text,
                      english: _verbEnglishController.text,
                    )
                  : _frontController.text.trim(),
      TranslationDirection.enToPl => _isNoun
          ? _nounSourceText(
              direction: direction,
              polishSingular: _nounPolishSingularController.text,
              polishPlural: _nounPolishPluralController.text,
              english: _nounEnglishController.text,
            )
          : _isAdjective
              ? _adjectiveSourceText(
                  direction: direction,
                  polishMasculine: _adjectivePolishMasculineController.text,
                  polishFeminine: _adjectivePolishFeminineController.text,
                  polishNeuter: _adjectivePolishNeuterController.text,
                  english: _adjectiveEnglishController.text,
                )
              : _isVerb
                  ? _verbSourceText(
                      direction: direction,
                      polishImperfective:
                          _verbPolishImperfectiveController.text,
                      polishPerfective: _verbPolishPerfectiveController.text,
                      english: _verbEnglishController.text,
                    )
                  : _backController.text.trim(),
    };
    if (sourceText.isEmpty) {
      setState(() {
        _error = direction == TranslationDirection.plToEn
            ? 'Add Polish text first.'
            : 'Add English text first.';
      });
      return;
    }

    setState(() {
      if (direction == TranslationDirection.plToEn) {
        _translatingToEnglish = true;
      } else {
        _translatingToPolish = true;
      }
      _error = null;
    });

    try {
      final nounTranslation = _isNoun
          ? await widget.api.translateNounText(
              text: sourceText,
              direction: direction,
            )
          : null;
      final adjectiveTranslation = _isAdjective
          ? await widget.api.translateAdjectiveText(
              text: sourceText,
              direction: direction,
            )
          : null;
      final verbTranslation = _isVerb
          ? await widget.api.translateVerbText(
              text: sourceText,
              direction: direction,
            )
          : null;
      final translation = _isNoun || _isAdjective || _isVerb
          ? null
          : await widget.api.translateText(
              text: sourceText,
              direction: direction,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        if (_isNoun) {
          _applyNounTranslation(
            translation: nounTranslation!,
            polishSingularController: _nounPolishSingularController,
            polishPluralController: _nounPolishPluralController,
            englishController: _nounEnglishController,
          );
        } else if (_isAdjective) {
          _applyAdjectiveTranslation(
            translation: adjectiveTranslation!,
            polishMasculineController: _adjectivePolishMasculineController,
            polishFeminineController: _adjectivePolishFeminineController,
            polishNeuterController: _adjectivePolishNeuterController,
            englishController: _adjectiveEnglishController,
          );
        } else if (_isVerb) {
          _applyVerbTranslation(
            translation: verbTranslation!,
            polishImperfectiveController: _verbPolishImperfectiveController,
            polishPerfectiveController: _verbPolishPerfectiveController,
            englishController: _verbEnglishController,
          );
        } else if (direction == TranslationDirection.plToEn) {
          _backController.text = translation!;
        } else {
          _frontController.text = translation!;
        }
      });
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
      setState(() => _error = 'Failed to translate');
    } finally {
      if (mounted) {
        setState(() {
          if (direction == TranslationDirection.plToEn) {
            _translatingToEnglish = false;
          } else {
            _translatingToPolish = false;
          }
        });
      }
    }
  }

  Future<void> _save() async {
    final front = _frontValue;
    final back = _backValue;
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
            if (_isNoun) ...[
              TextField(
                controller: _nounPolishSingularController,
                decoration: const InputDecoration(
                  labelText: 'Polish singular',
                  hintText: 'e.g. ten dom',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nounPolishPluralController,
                decoration: const InputDecoration(
                  labelText: 'Polish plural',
                  hintText: 'e.g. te domy',
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _saving || _translatingToEnglish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.plToEn,
                              ),
                      icon: _translatingToEnglish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_downward),
                      tooltip: 'Translate Polish to English',
                    ),
                    IconButton(
                      onPressed: _saving || _translatingToPolish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.enToPl,
                              ),
                      icon: _translatingToPolish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward),
                      tooltip: 'Translate English to Polish',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _nounEnglishController,
                decoration: const InputDecoration(
                  labelText: 'English singular',
                  hintText: 'e.g. house',
                ),
                maxLines: 1,
              ),
            ] else if (_isAdjective) ...[
              TextField(
                controller: _adjectivePolishMasculineController,
                decoration: const InputDecoration(
                  labelText: 'Polish masculine',
                  hintText: 'e.g. dobry',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adjectivePolishFeminineController,
                decoration: const InputDecoration(
                  labelText: 'Polish feminine',
                  hintText: 'e.g. dobra',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adjectivePolishNeuterController,
                decoration: const InputDecoration(
                  labelText: 'Polish neuter',
                  hintText: 'e.g. dobre',
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _saving || _translatingToEnglish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.plToEn,
                              ),
                      icon: _translatingToEnglish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_downward),
                      tooltip: 'Translate Polish to English',
                    ),
                    IconButton(
                      onPressed: _saving || _translatingToPolish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.enToPl,
                              ),
                      icon: _translatingToPolish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward),
                      tooltip: 'Translate English to Polish',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _adjectiveEnglishController,
                decoration: const InputDecoration(
                  labelText: 'English adjective',
                  hintText: 'e.g. good',
                ),
                maxLines: 1,
              ),
            ] else if (_isVerb) ...[
              TextField(
                controller: _verbPolishImperfectiveController,
                decoration: const InputDecoration(
                  labelText: 'Polish imperfective',
                  hintText: 'e.g. czytać',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _verbPolishPerfectiveController,
                decoration: const InputDecoration(
                  labelText: 'Polish perfective',
                  hintText: 'e.g. przeczytać',
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _saving || _translatingToEnglish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.plToEn,
                              ),
                      icon: _translatingToEnglish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_downward),
                      tooltip: 'Translate Polish to English',
                    ),
                    IconButton(
                      onPressed: _saving || _translatingToPolish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.enToPl,
                              ),
                      icon: _translatingToPolish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward),
                      tooltip: 'Translate English to Polish',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _verbEnglishController,
                decoration: const InputDecoration(
                  labelText: 'English verb',
                  hintText: 'e.g. read',
                ),
                maxLines: 1,
              ),
            ] else ...[
              TextField(
                controller: _frontController,
                decoration: const InputDecoration(labelText: 'Polish'),
              ),
              const SizedBox(height: 4),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _saving || _translatingToEnglish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.plToEn,
                              ),
                      icon: _translatingToEnglish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_downward),
                      tooltip: 'Translate Polish to English',
                    ),
                    IconButton(
                      onPressed: _saving || _translatingToPolish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.enToPl,
                              ),
                      icon: _translatingToPolish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward),
                      tooltip: 'Translate English to Polish',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _backController,
                decoration: const InputDecoration(labelText: 'English'),
                maxLines: 3,
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _hintController,
              decoration: const InputDecoration(labelText: 'Hint (optional)'),
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

class _EditCardDialog extends StatefulWidget {
  final ApiClient api;
  final CardModel card;
  final Future<void> Function()? onUnauthorized;

  const _EditCardDialog({
    required this.api,
    required this.card,
    this.onUnauthorized,
  });

  @override
  State<_EditCardDialog> createState() => _EditCardDialogState();
}

class _EditCardDialogState extends State<_EditCardDialog> {
  late final TextEditingController _frontController;
  late final TextEditingController _backController;
  late final TextEditingController _hintController;
  late final TextEditingController _nounPolishSingularController;
  late final TextEditingController _nounPolishPluralController;
  late final TextEditingController _nounEnglishController;
  late final TextEditingController _adjectivePolishMasculineController;
  late final TextEditingController _adjectivePolishFeminineController;
  late final TextEditingController _adjectivePolishNeuterController;
  late final TextEditingController _adjectiveEnglishController;
  late final TextEditingController _verbPolishImperfectiveController;
  late final TextEditingController _verbPolishPerfectiveController;
  late final TextEditingController _verbEnglishController;

  late CardType _cardType;
  bool _translatingToEnglish = false;
  bool _translatingToPolish = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cardType = widget.card.cardType;
    _frontController = TextEditingController(text: widget.card.front);
    _backController = TextEditingController(text: widget.card.back);
    _hintController = TextEditingController(text: widget.card.hint ?? '');
    final nounSplit = _splitNounFront(widget.card.front);
    _nounPolishSingularController =
        TextEditingController(text: nounSplit.singular);
    _nounPolishPluralController =
        TextEditingController(text: nounSplit.plural);
    _nounEnglishController = TextEditingController(text: widget.card.back);
    final adjectiveSplit = _splitAdjectiveFront(widget.card.front);
    _adjectivePolishMasculineController =
        TextEditingController(text: adjectiveSplit.masculine);
    _adjectivePolishFeminineController =
        TextEditingController(text: adjectiveSplit.feminine);
    _adjectivePolishNeuterController =
        TextEditingController(text: adjectiveSplit.neuter);
    _adjectiveEnglishController = TextEditingController(text: widget.card.back);
    final verbSplit = _splitVerbFront(widget.card.front);
    _verbPolishImperfectiveController =
        TextEditingController(text: verbSplit.imperfective);
    _verbPolishPerfectiveController =
        TextEditingController(text: verbSplit.perfective);
    _verbEnglishController = TextEditingController(text: widget.card.back);
  }

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    _hintController.dispose();
    _nounPolishSingularController.dispose();
    _nounPolishPluralController.dispose();
    _nounEnglishController.dispose();
    _adjectivePolishMasculineController.dispose();
    _adjectivePolishFeminineController.dispose();
    _adjectivePolishNeuterController.dispose();
    _adjectiveEnglishController.dispose();
    _verbPolishImperfectiveController.dispose();
    _verbPolishPerfectiveController.dispose();
    _verbEnglishController.dispose();
    super.dispose();
  }

  bool get _isNoun => _cardType == CardType.noun;
  bool get _isAdjective => _cardType == CardType.adjective;
  bool get _isVerb => _cardType == CardType.verb;

  Future<void> _translate({
    required TranslationDirection direction,
  }) async {
    final sourceText = switch (direction) {
      TranslationDirection.plToEn => _isNoun
          ? _nounSourceText(
              direction: direction,
              polishSingular: _nounPolishSingularController.text,
              polishPlural: _nounPolishPluralController.text,
              english: _nounEnglishController.text,
            )
          : _isAdjective
              ? _adjectiveSourceText(
                  direction: direction,
                  polishMasculine: _adjectivePolishMasculineController.text,
                  polishFeminine: _adjectivePolishFeminineController.text,
                  polishNeuter: _adjectivePolishNeuterController.text,
                  english: _adjectiveEnglishController.text,
                )
              : _isVerb
                  ? _verbSourceText(
                      direction: direction,
                      polishImperfective: _verbPolishImperfectiveController.text,
                      polishPerfective: _verbPolishPerfectiveController.text,
                      english: _verbEnglishController.text,
                    )
                  : _frontController.text.trim(),
      TranslationDirection.enToPl => _isNoun
          ? _nounSourceText(
              direction: direction,
              polishSingular: _nounPolishSingularController.text,
              polishPlural: _nounPolishPluralController.text,
              english: _nounEnglishController.text,
            )
          : _isAdjective
              ? _adjectiveSourceText(
                  direction: direction,
                  polishMasculine: _adjectivePolishMasculineController.text,
                  polishFeminine: _adjectivePolishFeminineController.text,
                  polishNeuter: _adjectivePolishNeuterController.text,
                  english: _adjectiveEnglishController.text,
                )
              : _isVerb
                  ? _verbSourceText(
                      direction: direction,
                      polishImperfective: _verbPolishImperfectiveController.text,
                      polishPerfective: _verbPolishPerfectiveController.text,
                      english: _verbEnglishController.text,
                    )
                  : _backController.text.trim(),
    };
    if (sourceText.isEmpty) {
      setState(() {
        _error = direction == TranslationDirection.plToEn
            ? 'Add Polish text first.'
            : 'Add English text first.';
      });
      return;
    }

    setState(() {
      if (direction == TranslationDirection.plToEn) {
        _translatingToEnglish = true;
      } else {
        _translatingToPolish = true;
      }
      _error = null;
    });

    try {
      final nounTranslation = _isNoun
          ? await widget.api.translateNounText(
              text: sourceText,
              direction: direction,
            )
          : null;
      final adjectiveTranslation = _isAdjective
          ? await widget.api.translateAdjectiveText(
              text: sourceText,
              direction: direction,
            )
          : null;
      final verbTranslation = _isVerb
          ? await widget.api.translateVerbText(
              text: sourceText,
              direction: direction,
            )
          : null;
      final translation = _isNoun || _isAdjective || _isVerb
          ? null
          : await widget.api.translateText(
              text: sourceText,
              direction: direction,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        if (_isNoun) {
          _applyNounTranslation(
            translation: nounTranslation!,
            polishSingularController: _nounPolishSingularController,
            polishPluralController: _nounPolishPluralController,
            englishController: _nounEnglishController,
          );
        } else if (_isAdjective) {
          _applyAdjectiveTranslation(
            translation: adjectiveTranslation!,
            polishMasculineController: _adjectivePolishMasculineController,
            polishFeminineController: _adjectivePolishFeminineController,
            polishNeuterController: _adjectivePolishNeuterController,
            englishController: _adjectiveEnglishController,
          );
        } else if (_isVerb) {
          _applyVerbTranslation(
            translation: verbTranslation!,
            polishImperfectiveController: _verbPolishImperfectiveController,
            polishPerfectiveController: _verbPolishPerfectiveController,
            englishController: _verbEnglishController,
          );
        } else if (direction == TranslationDirection.plToEn) {
          _backController.text = translation!;
        } else {
          _frontController.text = translation!;
        }
      });
    } on UnauthorizedException {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Session expired. Please log in again.');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Failed to translate');
    } finally {
      if (mounted) {
        setState(() {
          if (direction == TranslationDirection.plToEn) {
            _translatingToEnglish = false;
          } else {
            _translatingToPolish = false;
          }
        });
      }
    }
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
            if (_isNoun) ...[
              TextField(
                controller: _nounPolishSingularController,
                decoration: const InputDecoration(
                  labelText: 'Polish singular',
                  hintText: 'e.g. ten dom',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nounPolishPluralController,
                decoration: const InputDecoration(
                  labelText: 'Polish plural',
                  hintText: 'e.g. te domy',
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _translatingToEnglish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.plToEn,
                              ),
                      icon: _translatingToEnglish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_downward),
                      tooltip: 'Translate Polish to English',
                    ),
                    IconButton(
                      onPressed: _translatingToPolish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.enToPl,
                              ),
                      icon: _translatingToPolish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward),
                      tooltip: 'Translate English to Polish',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _nounEnglishController,
                decoration: const InputDecoration(
                  labelText: 'English singular',
                  hintText: 'e.g. house',
                ),
              ),
            ] else if (_isAdjective) ...[
              TextField(
                controller: _adjectivePolishMasculineController,
                decoration: const InputDecoration(
                  labelText: 'Polish masculine',
                  hintText: 'e.g. dobry',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adjectivePolishFeminineController,
                decoration: const InputDecoration(
                  labelText: 'Polish feminine',
                  hintText: 'e.g. dobra',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adjectivePolishNeuterController,
                decoration: const InputDecoration(
                  labelText: 'Polish neuter',
                  hintText: 'e.g. dobre',
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _translatingToEnglish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.plToEn,
                              ),
                      icon: _translatingToEnglish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_downward),
                      tooltip: 'Translate Polish to English',
                    ),
                    IconButton(
                      onPressed: _translatingToPolish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.enToPl,
                              ),
                      icon: _translatingToPolish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward),
                      tooltip: 'Translate English to Polish',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _adjectiveEnglishController,
                decoration: const InputDecoration(
                  labelText: 'English adjective',
                  hintText: 'e.g. good',
                ),
              ),
            ] else if (_isVerb) ...[
              TextField(
                controller: _verbPolishImperfectiveController,
                decoration: const InputDecoration(
                  labelText: 'Polish imperfective',
                  hintText: 'e.g. czytać',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _verbPolishPerfectiveController,
                decoration: const InputDecoration(
                  labelText: 'Polish perfective',
                  hintText: 'e.g. przeczytać',
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _translatingToEnglish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.plToEn,
                              ),
                      icon: _translatingToEnglish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_downward),
                      tooltip: 'Translate Polish to English',
                    ),
                    IconButton(
                      onPressed: _translatingToPolish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.enToPl,
                              ),
                      icon: _translatingToPolish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward),
                      tooltip: 'Translate English to Polish',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _verbEnglishController,
                decoration: const InputDecoration(
                  labelText: 'English verb',
                  hintText: 'e.g. read',
                ),
              ),
            ] else ...[
              TextField(
                controller: _frontController,
                decoration: const InputDecoration(labelText: 'Polish'),
              ),
              const SizedBox(height: 4),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _translatingToEnglish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.plToEn,
                              ),
                      icon: _translatingToEnglish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_downward),
                      tooltip: 'Translate Polish to English',
                    ),
                    IconButton(
                      onPressed: _translatingToPolish
                          ? null
                          : () => _translate(
                                direction: TranslationDirection.enToPl,
                              ),
                      icon: _translatingToPolish
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward),
                      tooltip: 'Translate English to Polish',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _backController,
                decoration: const InputDecoration(labelText: 'English'),
                maxLines: 3,
              ),
            ],
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
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
            final front = _isNoun
                ? _joinNounFront(
                    _nounPolishSingularController.text,
                    _nounPolishPluralController.text,
                  )
                : _isAdjective
                    ? _joinAdjectiveFront(
                        _adjectivePolishMasculineController.text,
                        _adjectivePolishFeminineController.text,
                        _adjectivePolishNeuterController.text,
                      )
                    : _isVerb
                        ? _joinVerbFront(
                            _verbPolishImperfectiveController.text,
                            _verbPolishPerfectiveController.text,
                          )
                        : _frontController.text.trim();
            final back = _isNoun
                ? _nounEnglishController.text.trim()
                : _isAdjective
                    ? _adjectiveEnglishController.text.trim()
                    : _isVerb
                        ? _verbEnglishController.text.trim()
                        : _backController.text.trim();
            final hint = _hintController.text.trim();
            if (front.isEmpty || back.isEmpty) {
              setState(() {
                _error = 'Polish and English are required.';
              });
              return;
            }
            Navigator.of(context).pop(_EditCardResult(
              shouldSave: true,
              front: front,
              back: back,
              hint: hint,
              cardType: _cardType,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditCardResult {
  final bool shouldSave;
  final String front;
  final String back;
  final String hint;
  final CardType cardType;

  _EditCardResult({
    required this.shouldSave,
    required this.front,
    required this.back,
    required this.hint,
    required this.cardType,
  });
}
