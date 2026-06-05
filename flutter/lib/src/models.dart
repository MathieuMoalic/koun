enum ReviewRating { again, hard, good, easy }

enum Algorithm { sm2, fsrs, leitner }

class CardModel {
  final int id;
  final String front;
  final String back;
  final String? hint;
  final bool suspended;

  CardModel({
    required this.id,
    required this.front,
    required this.back,
    required this.hint,
    required this.suspended,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] as int,
      front: json['front'] as String,
      back: json['back'] as String,
      hint: json['hint'] as String?,
      suspended: json['suspended'] as bool? ?? false,
    );
  }
}

class CardWithDue {
  final CardModel card;
  final int dueAt;
  final Algorithm algorithm;

  CardWithDue({required this.card, required this.dueAt, required this.algorithm});

  factory CardWithDue.fromJson(Map<String, dynamic> json) {
    return CardWithDue(
      card: CardModel.fromJson(json['card'] as Map<String, dynamic>),
      dueAt: json['due_at'] as int,
      algorithm: Algorithm.values.firstWhere(
        (value) => value.name == json['algorithm'],
        orElse: () => Algorithm.sm2,
      ),
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
