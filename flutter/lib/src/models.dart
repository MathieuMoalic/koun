enum ReviewRating { again, hard, good, easy }

enum CardType { noun, verb, adjective, phrase }

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

class ReviewCard {
  final int id;
  final String front;
  final String back;
  final String? hint;
  final bool suspended;

  ReviewCard({
    required this.id,
    required this.front,
    required this.back,
    required this.hint,
    required this.suspended,
  });

  factory ReviewCard.fromJson(Map<String, dynamic> json) {
    return ReviewCard(
      id: json['id'] as int,
      front: json['front'] as String,
      back: json['back'] as String,
      hint: json['hint'] as String?,
      suspended: json['suspended'] as bool? ?? false,
    );
  }
}

class CardWithDue {
  final ReviewCard card;
  final int dueAt;

  CardWithDue({required this.card, required this.dueAt});

  factory CardWithDue.fromJson(Map<String, dynamic> json) {
    return CardWithDue(
      card: ReviewCard.fromJson(json['card'] as Map<String, dynamic>),
      dueAt: json['due_at'] as int,
    );
  }
}

class NextReviewResponse {
  final CardWithDue? next;
  final int dueCount;

  NextReviewResponse({required this.next, required this.dueCount});

  factory NextReviewResponse.fromJson(Map<String, dynamic> json) {
    final nextJson = json['next'];
    return NextReviewResponse(
      next: nextJson == null
          ? null
          : CardWithDue.fromJson(nextJson as Map<String, dynamic>),
      dueCount: json['due_count'] as int,
    );
  }
}

class ReviewEvent {
  final int cardId;
  final ReviewRating rating;
  final int reviewedAt;

  ReviewEvent({
    required this.cardId,
    required this.rating,
    required this.reviewedAt,
  });

  Map<String, dynamic> toJson() => {
        'card_id': cardId,
        'rating': rating.name,
        'reviewed_at': reviewedAt,
      };
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

  FsrsSettings({
    required this.desiredRetention,
    required this.learningStep1Minutes,
    required this.learningStep2Minutes,
    required this.relearningStepMinutes,
  });

  factory FsrsSettings.fromJson(Map<String, dynamic> json) {
    return FsrsSettings(
      desiredRetention: (json['desired_retention'] as num).toDouble(),
      learningStep1Minutes: json['learning_step_1_minutes'] as int,
      learningStep2Minutes: json['learning_step_2_minutes'] as int,
      relearningStepMinutes: json['relearning_step_minutes'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'desired_retention': desiredRetention,
        'learning_step_1_minutes': learningStep1Minutes,
        'learning_step_2_minutes': learningStep2Minutes,
        'relearning_step_minutes': relearningStepMinutes,
      };
}

class VersionInfo {
  final String version;

  VersionInfo({required this.version});

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(version: json['version'] as String);
  }
}
