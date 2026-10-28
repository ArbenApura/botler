// THE PHOTOS OF ONE MESSAGE: HOW MANY THERE MAY BE AND HOW MUCH OF THEIR TEXT IS SENT. THE SERVER REFUSES MORE (server/src/lib/server/agent/prompt.ts).
// Every photo is read on the phone. Only the words go to the server, and the budget is kept here so a send never fails for being too long.

// -- CONSTANTS -- //

/// Photos in one message.
const int maxPhotos = 6;

/// Characters of one photo.
const int maxPhotoChars = 8000;

/// Characters of all the photos of one message together.
const int maxPhotosTotalChars = 24000;

// -- TYPES -- //

/// One photo that was read: where it came from (to tell a picture chosen twice) and the text on it.
class PhotoNote {
  const PhotoNote(this.path, this.text);

  final String path;
  final String text;
}

/// The texts to send, and whether any of them had to be cut to fit.
class PhotoBudget {
  const PhotoBudget(this.texts, {required this.trimmed});

  final List<String> texts;
  final bool trimmed;
}

// -- FUNCTIONS -- //

/// Cuts the texts so that together they stay within [maxPhotosTotalChars] and none passes [maxPhotoChars]. A short photo keeps all of
/// its text and the long ones share what is left, each cut to the same length.
PhotoBudget fitPhotoTexts(List<String> texts) {
  final capped = <String>[
    for (final t in texts)
      t.length > maxPhotoChars ? t.substring(0, maxPhotoChars) : t,
  ];
  var total = 0;
  for (final t in capped) {
    total += t.length;
  }
  var cut = capped.length != texts.length || total != _sum(texts);
  if (total <= maxPhotosTotalChars) {
    return PhotoBudget(capped, trimmed: cut);
  }
  // The longest each photo may be so that the sum fits: found by halving, because the sum only grows with the limit
  var low = 0;
  var high = maxPhotoChars;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    var sum = 0;
    for (final t in capped) {
      sum += t.length < mid ? t.length : mid;
    }
    if (sum <= maxPhotosTotalChars) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  cut = true;
  return PhotoBudget(<String>[
    for (final t in capped) t.length > low ? t.substring(0, low) : t,
  ], trimmed: cut);
}

int _sum(List<String> texts) {
  var n = 0;
  for (final t in texts) {
    n += t.length;
  }
  return n;
}
