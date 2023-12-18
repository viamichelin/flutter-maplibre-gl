part of maplibre_gl;

Map<String, dynamic> buildFeatureCollection(
    List<Map<String, dynamic>> features) {
  return {"type": "FeatureCollection", "features": features};
}

final _random = Random();

final _ids = <String>{};

String getRandomString([int length = 10]) {
  const charSet =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  final randomString = String.fromCharCodes(Iterable.generate(
      length, (_) => charSet.codeUnitAt(_random.nextInt(charSet.length))));
  if (_ids.contains(randomString)) {
    print("DUPLICATE ID!!!!!!!");
    return getRandomString();
  }

  _ids.add(randomString);
  return randomString;
}
