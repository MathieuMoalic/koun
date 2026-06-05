enum ReviewRating { again, hard, good, easy }

class CardModel {
  final int id;
  final String front;
  final String back;
  final String? hint;
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
  final List<String> learningSteps;
  final List<String> relearningSteps;

  FsrsSettings({
    required this.desiredRetention,
    required this.learningSteps,
    required this.relearningSteps,
  });

  factory FsrsSettings.fromJson(Map<String, dynamic> json) {
    return FsrsSettings(
      desiredRetention: (json['desired_retention'] as num).toDouble(),
      learningSteps: (json['learning_steps'] as List<dynamic>)
          .map((value) => value as String)
          .toList(),
      relearningSteps: (json['relearning_steps'] as List<dynamic>)
          .map((value) => value as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'desired_retention': desiredRetention,
        'learning_steps': learningSteps,
        'relearning_steps': relearningSteps,
      };
}
