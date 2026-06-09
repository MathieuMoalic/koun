import 'dart:io';

import 'package:flutter/services.dart';

class CardAudioPlayer {
  static const MethodChannel _channel = MethodChannel('koun/audio');

  Future<void> playBytes(List<int> bytes, {required int cardId}) async {
    final file = File('${Directory.systemTemp.path}/card-$cardId.mp3');
    await file.writeAsBytes(bytes, flush: true);
    await _channel.invokeMethod<void>('playFile', {'path': file.path});
  }
}

CardAudioPlayer createCardAudioPlayer() => CardAudioPlayer();
