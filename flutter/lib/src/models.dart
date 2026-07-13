enum ReviewRating { again, hard, good, easy }

enum CardType { noun, verb, adjective, phrase }

enum TranslationDirection { plToEn, enToPl }

enum ReviewDirection { plToEn, enToPl }

extension CardTypeX on CardType {
  String get label => switch (this) {
        CardType.noun => 'Noun',
        CardType.verb => 'Verb',
        CardType.adjective => 'Adjective',
        CardType.phrase => 'Phrase',
      };

  static CardType fromJson(String? value) {
    switch (value?.toLowerCase()) {
      case 'verb':
        return CardType.verb;
      case 'adjective':
        return CardType.adjective;
      case 'phrase':
        return CardType.phrase;
      case 'noun':
      default:
        return CardType.noun;
    }
  }

  String formatEnglish(String value) {
    final trimmed = value.trim();
    if (this == CardType.verb && trimmed.isNotEmpty) {
      return trimmed.startsWith('to ') ? trimmed : 'to $trimmed';
    }
    return trimmed;
  }
}

extension TranslationDirectionX on TranslationDirection {
  String get label => switch (this) {
        TranslationDirection.plToEn => 'Translate to English',
        TranslationDirection.enToPl => 'Translate to Polish',
      };

  String get apiValue => switch (this) {
        TranslationDirection.plToEn => 'pl_to_en',
        TranslationDirection.enToPl => 'en_to_pl',
      };
}

extension ReviewDirectionX on ReviewDirection {
  static ReviewDirection fromJson(String? value) {
    switch (value) {
      case 'en_to_pl':
        return ReviewDirection.enToPl;
      case 'pl_to_en':
      default:
        return ReviewDirection.plToEn;
    }
  }
}

class CardModel {
  final int id;
  final String front;
  final String back;
  final String? hint;
  final CardType cardType;
  final bool audioAvailable;
  final bool suspended;
  final int createdAt;
  final int updatedAt;
  final double fsrsStability;
  final double fsrsDifficulty;
  final double fsrsRetrievability;
  final int fsrsDueAt;
  final int fsrsLastReviewAt;

  CardModel({
    required this.id,
    required this.front,
    required this.back,
    required this.hint,
    required this.cardType,
    required this.audioAvailable,
    required this.suspended,
    required this.createdAt,
    required this.updatedAt,
    required this.fsrsStability,
    required this.fsrsDifficulty,
    required this.fsrsRetrievability,
    required this.fsrsDueAt,
    required this.fsrsLastReviewAt,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] as int,
      front: json['front'] as String,
      back: json['back'] as String,
      hint: json['hint'] as String?,
      cardType: CardTypeX.fromJson(json['card_type'] as String?),
      audioAvailable: json['audio_available'] as bool? ?? false,
      suspended: json['suspended'] as bool? ?? false,
      createdAt: json['created_at'] as int,
      updatedAt: json['updated_at'] as int,
      fsrsStability: (json['fsrs_stability'] as num).toDouble(),
      fsrsDifficulty: (json['fsrs_difficulty'] as num).toDouble(),
      fsrsRetrievability: (json['fsrs_retrievability'] as num).toDouble(),
      fsrsDueAt: json['fsrs_due_at'] as int,
      fsrsLastReviewAt: json['fsrs_last_review_at'] as int,
    );
  }
}

class ReviewItem {
  final int cardId;
  final int cardDirectionId;
  final ReviewDirection direction;
  final String prompt;
  final String answer;
  final String? hint;
  final CardType cardType;
  final int dueAt;

  ReviewItem({
    required this.cardId,
    required this.cardDirectionId,
    required this.direction,
    required this.prompt,
    required this.answer,
    required this.hint,
    required this.cardType,
    required this.dueAt,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    return ReviewItem(
      cardId: json['card_id'] as int,
      cardDirectionId: json['card_direction_id'] as int,
      direction: ReviewDirectionX.fromJson(json['direction'] as String?),
      prompt: json['prompt'] as String,
      answer: json['answer'] as String,
      hint: json['hint'] as String?,
      cardType: CardTypeX.fromJson(json['card_type'] as String?),
      dueAt: json['due_at'] as int,
    );
  }
}

class NextReviewResponse {
  final ReviewItem? next;
  final int dueCount;
  final int newCardsLearned;
  final int oldCardsReviewed;

  NextReviewResponse({
    required this.next,
    required this.dueCount,
    required this.newCardsLearned,
    required this.oldCardsReviewed,
  });

  factory NextReviewResponse.fromJson(Map<String, dynamic> json) {
    final nextJson = json['next'];
    return NextReviewResponse(
      next: nextJson == null
          ? null
          : ReviewItem.fromJson(nextJson as Map<String, dynamic>),
      dueCount: json['due_count'] as int,
      newCardsLearned: json['new_cards_learned'] as int? ?? 0,
      oldCardsReviewed: json['old_cards_reviewed'] as int? ?? 0,
    );
  }
}

class ReviewEvent {
  final int? cardDirectionId;
  final int? cardId;
  final ReviewRating rating;
  final int reviewedAt;

  ReviewEvent({
    this.cardDirectionId,
    this.cardId,
    required this.rating,
    required this.reviewedAt,
  }) : assert(cardDirectionId != null || cardId != null);

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'rating': rating.name,
      'reviewed_at': reviewedAt,
    };
    if (cardDirectionId != null) {
      data['card_direction_id'] = cardDirectionId;
    }
    if (cardId != null) {
      data['card_id'] = cardId;
    }
    return data;
  }
}

class ReviewsPerDay {
  final String day;
  final int count;

  ReviewsPerDay({required this.day, required this.count});

  factory ReviewsPerDay.fromJson(Map<String, dynamic> json) {
    return ReviewsPerDay(
      day: json['day'] as String,
      count: json['count'] as int,
    );
  }
}

class FsrsSettings {
  final double desiredRetention;
  final int learningStep1Minutes;
  final int learningStep2Minutes;
  final int relearningStepMinutes;
  final int newCardsPerDay;
  final int oldCardsPerDay;

  FsrsSettings({
    required this.desiredRetention,
    required this.learningStep1Minutes,
    required this.learningStep2Minutes,
    required this.relearningStepMinutes,
    required this.newCardsPerDay,
    required this.oldCardsPerDay,
  });

  factory FsrsSettings.fromJson(Map<String, dynamic> json) {
    return FsrsSettings(
      desiredRetention: (json['desired_retention'] as num).toDouble(),
      learningStep1Minutes: json['learning_step_1_minutes'] as int,
      learningStep2Minutes: json['learning_step_2_minutes'] as int,
      relearningStepMinutes: json['relearning_step_minutes'] as int,
      newCardsPerDay: json['new_cards_per_day'] as int? ?? 50,
      oldCardsPerDay: json['old_cards_per_day'] as int? ?? 200,
    );
  }

  Map<String, dynamic> toJson() => {
        'desired_retention': desiredRetention,
        'learning_step_1_minutes': learningStep1Minutes,
        'learning_step_2_minutes': learningStep2Minutes,
        'relearning_step_minutes': relearningStepMinutes,
        'new_cards_per_day': newCardsPerDay,
        'old_cards_per_day': oldCardsPerDay,
      };
}

class VersionInfo {
  final String version;

  VersionInfo({required this.version});

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(version: json['version'] as String);
  }
}
