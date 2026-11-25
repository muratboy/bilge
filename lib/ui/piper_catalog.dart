import 'package:flutter/foundation.dart';

/// Piper ses model tanımı.
@immutable
class PiperVoice {
  const PiperVoice({
    required this.id,
    required this.lang,
    required this.name,
    required this.onnxUrl,
    required this.onnxSize,
    required this.onnxSha256,
    required this.jsonUrl,
    required this.jsonSize,
    required this.jsonSha256,
    required this.license,
    this.isNonCommercial = false,
  });

  /// Ses kimliği (ör. tr_TR-dfki-medium).
  final String id;

  /// Dil ve bölge kodu (ör. tr_TR, en_US).
  final String lang;

  /// Görünen ad (ör. DFKI, Lessac).
  final String name;

  /// .onnx indirme adresi.
  final String onnxUrl;

  /// .onnx bayt boyutu.
  final int onnxSize;

  /// .onnx SHA-256 özeti.
  final String onnxSha256;

  /// .onnx.json indirme adresi.
  final String jsonUrl;

  /// .onnx.json bayt boyutu.
  final int jsonSize;

  /// .onnx.json SHA-256 özeti.
  final String jsonSha256;

  /// Veri seti lisansı (ör. CC0, CC BY 4.0, CC BY-NC-SA 4.0).
  final String license;

  /// Lisansın ticari olmayan (NC) kısıt taşıyıp taşımadığı.
  final bool isNonCommercial;

  /// Birincil dil kodu (ör. 'tr', 'en').
  String get primaryLang => lang.split('_').first.toLowerCase();

  /// Megabayt cinsinden yaklaşık boyut.
  double get sizeMb => onnxSize / (1024 * 1024);
}

/// Hugging Face rhasspy/piper-voices deposundan sabitlenmiş ses kataloğu.
class PiperCatalog {
  /// Kataloğun sabitlendiği commit kimliği.
  static const commit = '5ec43b186ef915a195d3ddbcfd9916e76c503c3f';

  /// Dil başına önizleme cümleleri.
  static const Map<String, String> previewSentences = {
    'tr': 'Merhaba! Ben Bilge. Birlikte öğrenelim.',
    'en': "Hello! I am Bilge. Let's learn together.",
    'de': 'Hallo! Ich bin Bilge. Lass uns zusammen lernen.',
    'fr': 'Bonjour ! Je suis Bilge. Apprenons ensemble.',
    'es': '¡Hola! Soy Bilge. Aprendamos juntos.',
    'it': 'Ciao! Sono Bilge. Impariamo insieme.',
    'pt': 'Olá! Eu sou a Bilge. Vamos aprender juntos.',
    'ru': 'Привет! Давай учиться вместе.',
    'ar': 'مرحبا! لنتعلم معا.',
    'nl': 'Hallo! Ik ben Bilge. Laten we samen leren.',
    'zh': '你好！我们一起学习吧。',
  };

  /// İstenen dil için önizleme cümlesi döner.
  static String previewSentenceFor(String lang) {
    final norm = lang.replaceAll('-', '_').toLowerCase().trim();
    final primary = norm.split('_').first;
    return previewSentences[primary] ?? previewSentences['tr']!;
  }

  /// Sabit ses listesi.
  static const List<PiperVoice> voices = [
    PiperVoice(
      id: 'tr_TR-dfki-medium',
      lang: 'tr_TR',
      name: 'DFKI',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/tr/tr_TR/dfki/medium/tr_TR-dfki-medium.onnx',
      onnxSize: 63201294,
      onnxSha256: '2844717f524ab965d3fe86e60562cbb601d3e456836efcc2196cc3a14112a8fb',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/tr/tr_TR/dfki/medium/tr_TR-dfki-medium.onnx.json',
      jsonSize: 4960,
      jsonSha256: '13ebd7810f1b61b5027583cf3131a0a233b6ea81c38f2200ebc4ff41c3cca039',
      license: 'CC BY-NC-SA 4.0',
      isNonCommercial: true,
    ),
    PiperVoice(
      id: 'en_US-lessac-medium',
      lang: 'en_US',
      name: 'Lessac',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/en/en_US/lessac/medium/en_US-lessac-medium.onnx',
      onnxSize: 63201294,
      onnxSha256: '5efe09e69902187827af646e1a6e9d269dee769f9877d17b16b1b46eeaaf019f',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json',
      jsonSize: 4885,
      jsonSha256: 'efe19c417bed055f2d69908248c6ba650fa135bc868b0e6abb3da181dab690a0',
      license: 'Blizzard (araştırma)',
      isNonCommercial: true,
    ),
    PiperVoice(
      id: 'en_US-amy-medium',
      lang: 'en_US',
      name: 'Amy',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/en/en_US/amy/medium/en_US-amy-medium.onnx',
      onnxSize: 63221984,
      onnxSha256: 'cf9ccdec59f05adee47173f6fb4d89e8b0c5f30c178748d2572fe4efd1d2724c',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/en/en_US/amy/medium/en_US-amy-medium.onnx.json',
      jsonSize: 6289,
      jsonSha256: '27490c2197e3e7b566b051fc0b1dae21200e72b44c209731419effdbbe0789e5',
      license: 'CC BY-SA 4.0',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'en_GB-alba-medium',
      lang: 'en_GB',
      name: 'Alba',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/en/en_GB/alba/medium/en_GB-alba-medium.onnx',
      onnxSize: 63221984,
      onnxSha256: '1f9da809b6da1ef4190bb5dd6cce4f4af803274539e9cf9e0693085150bac3d7',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/en/en_GB/alba/medium/en_GB-alba-medium.onnx.json',
      jsonSize: 6295,
      jsonSha256: 'ed4b1f015a8aae5eb26d4bdeed7b712c660f5698a0dd954aa6df9c8be60b900b',
      license: 'CC BY 4.0',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'de_DE-thorsten-medium',
      lang: 'de_DE',
      name: 'Thorsten',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx',
      onnxSize: 63221984,
      onnxSha256: 'fd270eb3d1ebf91d763f8a0f949b1b1bebdfefaea18c3aaf8577dd34536e064f',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx.json',
      jsonSize: 6455,
      jsonSha256: 'e5bb7410dcbbcc0be6f4544f6bc66612b315ab5cb3099ec44bb46d860bc7cca9',
      license: 'CC0',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'fr_FR-siwis-medium',
      lang: 'fr_FR',
      name: 'Siwis',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx',
      onnxSize: 63221984,
      onnxSha256: 'b1d946fd68d0347155fa59bce0a018924abbef3c1561181db45ca463d83963ef',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/fr/fr_FR/siwis/medium/fr_FR-siwis-medium.onnx.json',
      jsonSize: 6369,
      jsonSha256: '3b3efdbcdcae930c40d8255527170ec5c87bf05e510b67f53d75fd028df40f43',
      license: 'CC BY 4.0',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'es_ES-davefx-medium',
      lang: 'es_ES',
      name: 'Davefx',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/es/es_ES/davefx/medium/es_ES-davefx-medium.onnx',
      onnxSize: 63221984,
      onnxSha256: 'd2c9224e122321aac3c33343957fff4d0f465226cb74c66b0f520ca3f8c0dd07',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/es/es_ES/davefx/medium/es_ES-davefx-medium.onnx.json',
      jsonSize: 6175,
      jsonSha256: '7d82d069eccca0f87963bd23c33166fe1ef6d24a6b231543931bfe692397f256',
      license: 'CC0',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'it_IT-paola-medium',
      lang: 'it_IT',
      name: 'Paola',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/it/it_IT/paola/medium/it_IT-paola-medium.onnx',
      onnxSize: 63221984,
      onnxSha256: 'f9b8658aa8c01f8280aa88488f6e7643a639b6225a81514c40440a01f6364a20',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/it/it_IT/paola/medium/it_IT-paola-medium.onnx.json',
      jsonSize: 6114,
      jsonSha256: '10e46e8534dd2d4051f1534ba6542f189f854454acea44a6d45ff464a83260fa',
      license: 'CC0',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'pt_BR-faber-medium',
      lang: 'pt_BR',
      name: 'Faber',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx',
      onnxSize: 63221984,
      onnxSha256: '75e913eb463db0b6ac7ddf68d3e4c9ac19ace36dc3b710a81039b448352b8ffc',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/pt/pt_BR/faber/medium/pt_BR-faber-medium.onnx.json',
      jsonSize: 6257,
      jsonSha256: '6b6801319e5a70aa4d75c63343515f55d1cd671ecd1ac511586bc16216812261',
      license: 'CC0',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'ru_RU-irina-medium',
      lang: 'ru_RU',
      name: 'Irina',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx',
      onnxSize: 63201294,
      onnxSha256: '8ff38212d23da300bbe3705c645e6e5b9475f0bfde01558eb17813e22acaaaaa',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx.json',
      jsonSize: 4765,
      jsonSha256: 'c2ec28bb38e2b59e93b959b3e40348c1afebbd272f30fed5d41205d08e98a9d7',
      license: 'bilinmiyor',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'ar_JO-kareem-medium',
      lang: 'ar_JO',
      name: 'Kareem',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/ar/ar_JO/kareem/medium/ar_JO-kareem-medium.onnx',
      onnxSize: 63201294,
      onnxSha256: '9e95cab07b679da603bba17c4dec7ab3111320571964ee95c0379603c086491e',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/ar/ar_JO/kareem/medium/ar_JO-kareem-medium.onnx.json',
      jsonSize: 5024,
      jsonSha256: 'ea6d9b9d9076dbdb6bf5c98c6a141ef154959d2359709b37855727964e7d6c4d',
      license: 'CC BY-SA 4.0',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'nl_NL-mls-medium',
      lang: 'nl_NL',
      name: 'MLS',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/nl/nl_NL/mls/medium/nl_NL-mls-medium.onnx',
      onnxSize: 76584246,
      onnxSha256: '88312e0fbf505b87caf2373d94c1384892e86b1bf2ee482cf65dc8ba179cc7d3',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/nl/nl_NL/mls/medium/nl_NL-mls-medium.onnx.json',
      jsonSize: 5856,
      jsonSha256: '6ddb215d38f1392ab935ad45441b82ada1eeae0452a2d6849ed71ea4f2e0aa63',
      license: 'CC BY 4.0',
      isNonCommercial: false,
    ),
    PiperVoice(
      id: 'zh_CN-huayan-medium',
      lang: 'zh_CN',
      name: 'Huayan',
      onnxUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx',
      onnxSize: 63201294,
      onnxSha256: '9929917bf8cabb26fd528ea44d3a6699c11e87317a14765312420be230be0f3d',
      jsonUrl: 'https://huggingface.co/rhasspy/piper-voices/resolve/5ec43b186ef915a195d3ddbcfd9916e76c503c3f/zh/zh_CN/huayan/medium/zh_CN-huayan-medium.onnx.json',
      jsonSize: 4822,
      jsonSha256: 'd521dc45504a8ccc99e325822b35946dd701840bfb07e3dbb31a40929ed6a82b',
      license: 'bilinmiyor',
      isNonCommercial: false,
    ),
  ];

  /// Kimliğe göre ses arar.
  static PiperVoice? findById(String id) {
    for (final v in voices) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// Belirli bir dile ait sesleri döner.
  static List<PiperVoice> forLang(String lang) {
    final norm = lang.replaceAll('-', '_').toLowerCase().trim();
    final primary = norm.split('_').first;
    return voices.where((v) => v.lang.toLowerCase() == norm || v.primaryLang == primary).toList();
  }
}
