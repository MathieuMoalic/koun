import 'dart:html' as html;
import 'dart:typed_data';

class CardAudioPlayer {
  Future<void> playBytes(List<int> bytes, {required int cardId}) async {
    final blob = html.Blob(
      [Uint8List.fromList(bytes)],
      'audio/mpeg',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final audio = html.AudioElement()..src = url;
    audio.onEnded.first.then((_) {
      html.Url.revokeObjectUrl(url);
      audio.remove();
    });
    audio.onError.first.then((_) {
      html.Url.revokeObjectUrl(url);
      audio.remove();
    });
    await audio.play();
  }
}

CardAudioPlayer createCardAudioPlayer() => CardAudioPlayer();
