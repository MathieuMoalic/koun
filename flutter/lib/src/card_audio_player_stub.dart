class CardAudioPlayer {
  Future<void> playBytes(List<int> bytes, {required int cardId}) {
    throw UnsupportedError('Audio playback is not supported on this platform.');
  }
}

CardAudioPlayer createCardAudioPlayer() => CardAudioPlayer();
