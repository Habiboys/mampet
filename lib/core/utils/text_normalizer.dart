/// Normalizes dish names and aliases without AI:
/// case-insensitive, trimmed, diacritic-folded, punctuation stripped,
/// and multiple spaces collapsed.
String normalizeFoodText(String input) {
  var s = input.toLowerCase().trim();
  const accents = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ñ': 'n', 'ç': 'c',
  };
  accents.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAll(RegExp(r"[-_'.`,/()&!?]"), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}
