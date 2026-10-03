/// Bilge ekibi: her maskotun adı, kişiliği ve kendi ağzından konuşmaları (Türkçe ve İngilizce).
library;

import 'dart:math';

import '../l10n/l10n.dart';
import 'mascot_art.dart';

/// Bir karakterin tek dildeki metinleri.
class Voice {
  const Voice({
    required this.species,
    required this.trait,
    required this.bio,
    required this.greet,
    required this.praise,
    required this.oops,
    required this.intro,
    required this.poke,
    required this.finish,
    required this.perfect,
    required this.fail,
  });

  final String species;
  final String trait; // iki kelimelik kişilik özeti
  final String bio;
  final String greet;
  final List<String> praise; // doğru cevapta
  final List<String> oops; // yanlış cevapta
  final List<String> intro; // bilgi kartını sunarken
  final List<String> poke; // öğrenme ekranında kendisine dokunulunca
  final String finish, perfect, fail;
}

class Character {
  const Character({required this.id, required this.name, required this.color, required this.tr, required this.en});

  final MascotId id;
  final String name;
  final int color; // karaktere eşlik eden vurgu rengi (ARGB)
  final Voice tr, en;

  Voice get voice => L.code == 'en' ? en : tr;
  String pick(List<String> lines, Random random) => lines[random.nextInt(lines.length)];
}

const cast = <Character>[
  Character(
    id: MascotId.puhu,
    name: 'Puhu',
    color: 0xFF8A6652,
    tr: Voice(
      species: 'Baykuş',
      trait: 'Bilge profesör',
      bio: 'Ağırbaşlıdır, acele etmez. Bir şeyin yalnızca ne olduğunu değil, neden öyle olduğunu da bilmeni ister.',
      greet: 'Hoş geldin. Bugün neyin nedenini öğreniyoruz?',
      praise: ['Kusursuz bir akıl yürütme.', 'Tam da kitabın yazdığı gibi.', 'Doğru. Nedenini de biliyorsun, değil mi?', 'Not defterime yazdım: parlak öğrenci.'],
      oops: ['Hata, bilginin habercisidir.', 'Bir daha bakalım; acele yok.', 'İlginç bir fikir, ama doğrusu başka.'],
      intro: ['Şuna dikkat et:', 'Küçük bir ders notu:', 'Bunu bilmek işini kolaylaştırır:'],
      poke: ['Evet? Bir sorun mu var?', 'Dokunmak da bir tür gözlemdir.', 'Dersi mi özledin? Ben de.'],
      finish: 'Ders bitti. Aklında kalan artık senindir.',
      perfect: 'Tek hata yok. Kürsüyü sana bırakabilirim.',
      fail: 'Bilgi sabır ister. Bir kez daha deneyelim.',
    ),
    en: Voice(
      species: 'Owl',
      trait: 'Wise professor',
      bio: 'Dignified and never in a hurry. Wants you to know not just what something is, but why it is so.',
      greet: 'Welcome. Whose “why” are we learning today?',
      praise: ['Flawless reasoning.', 'Exactly as the book says.', 'Correct. And you know why, don’t you?', 'Noted in my ledger: a bright student.'],
      oops: ['A mistake is the herald of knowledge.', 'Let’s look again; there’s no rush.', 'An interesting idea, but the answer lies elsewhere.'],
      intro: ['Mark this:', 'A small lecture note:', 'Knowing this will make things easier:'],
      poke: ['Yes? Do you have a question?', 'Touching is a kind of observation, too.', 'Missing the lesson? So am I.'],
      finish: 'Class dismissed. What stayed with you is yours now.',
      perfect: 'Not a single error. I may hand you the lectern.',
      fail: 'Knowledge takes patience. Let’s try once more.',
    ),
  ),
  Character(
    id: MascotId.tarcin,
    name: 'Tarçın',
    color: 0xFFFF8A3D,
    tr: Voice(
      species: 'Tilki',
      trait: 'Kurnaz şakacı',
      bio: 'Muziptir, kestirme yolları sever. Tuzak şıkları senden önce koklar ama söylemez.',
      greet: 'Selam! Bugün hangi bilmeceyi çözüyoruz?',
      praise: ['Vay, kurnazsın!', 'Tuzağa düşmedin, helal!', 'Bunu ben bile daha hızlı bulamazdım.', 'Çaktırma ama çok iyisin.'],
      oops: ['Hop, tuzağa bastın!', 'O şık seni kandırdı.', 'Olsun, tilki de bir günde tilki olmadı.'],
      intro: ['Bir sır vereyim mi?', 'Kestirmesi şu:', 'Püf noktası:'],
      poke: ['Hop! Gıdıklanıyorum!', 'Kuyruğa dokunmak yok, o uğurlu.', 'Bir numara mı görmek istiyorsun?'],
      finish: 'Bitti bile! Bir tane daha kaçırsak mı?',
      perfect: 'Sıfır hata mı? Sen tilkinin dolaştığı yeri biliyorsun!',
      fail: 'Bu sefer sorular kazandı. Rövanşa var mısın?',
    ),
    en: Voice(
      species: 'Fox',
      trait: 'Sly joker',
      bio: 'Mischievous and fond of shortcuts. Sniffs out trick answers before you do, but won’t tell.',
      greet: 'Hey! Which riddle are we cracking today?',
      praise: ['Ooh, sly one!', 'Didn’t fall for the trap. Nice!', 'Even I couldn’t have found that faster.', 'Don’t let it show, but you’re really good.'],
      oops: ['Whoops, you stepped in the trap!', 'That option fooled you.', 'It’s fine. No fox became a fox in a day.'],
      intro: ['Want to hear a secret?', 'Here’s the shortcut:', 'The trick is:'],
      poke: ['Hey! That tickles!', 'Hands off the tail, it’s lucky.', 'Want to see a trick?'],
      finish: 'Done already! Shall we sneak in one more?',
      perfect: 'Zero mistakes? You know every trail in the woods!',
      fail: 'The questions won this round. Up for a rematch?',
    ),
  ),
  Character(
    id: MascotId.zifir,
    name: 'Zifir',
    color: 0xFF5B5380,
    tr: Voice(
      species: 'Kuzgun',
      trait: 'Alaycı gözlemci',
      bio: 'Az konuşur, zor beğenir. Ondan bir "fena değil" koparmak, başkasından alkış almaktan değerlidir.',
      greet: 'Geldin demek. Şaşırdım.',
      praise: ['Fena değil.', 'Hm. Bunu beklemiyordum.', 'Doğru. Abartmayalım ama doğru.', 'Tamam, etkilendim. Biraz.'],
      oops: ['Cesur bir tahmindi.', 'Yanlış. Ama kendinden emindin, o da bir şey.', 'Bunu görmemiş olayım.'],
      intro: ['Dinle, bir kere söylerim:', 'Sıkıcı ama önemli:', 'Not al:'],
      poke: ['Ne var?', 'Tüylerimi bozma.', 'Dokunmak bedava. Cevabı bilmek değil.'],
      finish: 'Bitirdin. Alkışlardım ama kanatlarım dolu.',
      perfect: 'Hatasız. Peki. Bunu kimseye söylemeyeceğim.',
      fail: 'Canların bitti, benim de sabrım. Yine de dene.',
    ),
    en: Voice(
      species: 'Raven',
      trait: 'Dry observer',
      bio: 'Says little and is hard to impress. A “not bad” from this one is worth more than applause from anyone else.',
      greet: 'So you came. I’m surprised.',
      praise: ['Not bad.', 'Hm. Didn’t expect that.', 'Correct. Let’s not overdo it, but correct.', 'Fine, I’m impressed. A little.'],
      oops: ['A bold guess.', 'Wrong. But you were confident, and that’s something.', 'I’ll pretend I didn’t see that.'],
      intro: ['Listen, I’ll say it once:', 'Boring but important:', 'Take note:'],
      poke: ['What?', 'Mind the feathers.', 'Poking is free. Knowing the answer isn’t.'],
      finish: 'You finished. I’d clap, but my wings are busy.',
      perfect: 'Flawless. Fine. I won’t tell anyone.',
      fail: 'You’re out of hearts and I’m out of patience. Try anyway.',
    ),
  ),
  Character(
    id: MascotId.tosbi,
    name: 'Tosbi',
    color: 0xFF3F8F5F,
    tr: Voice(
      species: 'Kaplumbağa',
      trait: 'Sabırlı dost',
      bio: 'Ekibin en yaşlısıdır; sakindir, kimseyi yarıştırmaz. Yanıldığında ilk o teselli eder: yol uzun, vakit çok.',
      greet: 'Hoş geldin. Acele yok, keyfini çıkar.',
      praise: ['Yavaş yavaş, tam isabet.', 'Adım adım geliyorsun.', 'Güzel. Nefes al, devam.', 'İşte böyle: sakin ve doğru.'],
      oops: ['Olsun. Yol uzun, vaktimiz çok.', 'Yanılmak da yolun parçası.', 'Bu soru yine gelir, o zaman bilirsin.'],
      intro: ['Şimdi ağır ağır bakalım:', 'Önce şunu sindirelim:', 'Sakin bir bilgi molası:'],
      poke: ['Buradayım, bir yere gitmiyorum.', 'Kabuğum gıdıklanmaz ama sağ ol.', 'Bir çay molası mı verelim?'],
      finish: 'Bir adım daha attın. En uzun yol da böyle biter.',
      perfect: 'Hiç tökezlemeden. Yavaş ama kusursuz.',
      fail: 'Bugünlük yorulduk. Dinlen, yine deneriz.',
    ),
    en: Voice(
      species: 'Turtle',
      trait: 'Patient friend',
      bio: 'The eldest of the crew: calm, and never makes it a race. The first to comfort you when you slip: the road is long and there’s plenty of time.',
      greet: 'Welcome. No rush, enjoy it.',
      praise: ['Slow and steady, right on target.', 'Step by step, you’re getting there.', 'Lovely. Breathe, and on we go.', 'Just like that: calm and correct.'],
      oops: ['That’s all right. The road is long and we have time.', 'Slipping is part of the path.', 'This one will come back, and then you’ll know it.'],
      intro: ['Let’s take this slowly:', 'First, let this sink in:', 'A quiet little fact break:'],
      poke: ['I’m here. Not going anywhere.', 'The shell isn’t ticklish, but thanks.', 'Shall we take a tea break?'],
      finish: 'One more step taken. That’s how the longest roads end.',
      perfect: 'Not one stumble. Slow, but flawless.',
      fail: 'We’re tired for today. Rest, and we’ll try again.',
    ),
  ),
  Character(
    id: MascotId.pasa,
    name: 'Paşa',
    color: 0xFF6E86AC,
    tr: Voice(
      species: 'Fil',
      trait: 'Hafıza ustası',
      bio: 'Babacandır ve hiçbir şeyi unutmaz. Yanlış yaptığın soruları bir kenara yazar, sonra sana yeniden sorar.',
      greet: 'Hoş geldin evladım! Kaldığımız yeri hatırlıyorum.',
      praise: ['Aferin evladım!', 'Maşallah, bunu artık unutmazsın.', 'Hafızana kazındı bile.', 'Helal olsun, ne güzel hatırladın!'],
      oops: ['Üzülme evladım, ben hatırlatırım.', 'Olur böyle şeyler; birlikte tekrar ederiz.', 'Bir kenara yazdım, yine soracağım.'],
      intro: ['Bunu aklında tut:', 'Unutma diye söylüyorum:', 'Hafızana bir not:'],
      poke: ['Buyur evladım?', 'Bunu da hafızama yazdım.', 'Bir şey mi unuttun? Ben hatırlarım.'],
      finish: 'Bugün öğrendiklerin artık seninle evladım. Ben de unutmam.',
      perfect: 'Hepsini hatırladın! Aferin, fil hafızası sende.',
      fail: 'Yoruldun galiba evladım. Dinlen; hazır olunca devam ederiz, buradayım.',
    ),
    en: Voice(
      species: 'Elephant',
      trait: 'Memory keeper',
      bio: 'Fatherly and never forgets a thing. Jots down the questions you miss and asks them again later.',
      greet: 'Welcome, my child! I remember where we left off.',
      praise: ['Well done, my child!', 'Bravo, you won’t forget that now.', 'It’s already etched in your memory.', 'How nicely you remembered!'],
      oops: ['Don’t worry, my child, I’ll remind you.', 'These things happen; we’ll go over it together.', 'I’ve written it down; I’ll ask again.'],
      intro: ['Keep this in mind:', 'I’m telling you so you don’t forget:', 'A note for your memory:'],
      poke: ['Yes, my child?', 'Noted. I’ll remember that, too.', 'Forgot something? I’ll remember it for you.'],
      finish: 'What you learned today stays with you. I won’t forget it either.',
      perfect: 'You remembered it all! You have an elephant’s memory.',
      fail: 'You seem tired, my child. Rest; I’ll be right here when you’re ready.',
    ),
  ),
  Character(
    id: MascotId.sekiz,
    name: 'Sekiz',
    color: 0xFFE0558A,
    tr: Voice(
      species: 'Ahtapot',
      trait: 'Meraklı mucit',
      bio: 'Her şeyi kurcalar, sekiz koluyla sekiz işe yetişir. Eşleştirme ve sıralama bulmacalarına bayılır.',
      greet: 'Oo geldin! Sekiz kolumla sekiz şey hazırladım!',
      praise: ['Buldun!', 'Parçalar yerine oturdu!', 'Deney başarılı!', 'Bunu sekiz kolla alkışlıyorum!'],
      oops: ['Deney patladı! Sorun değil, yenisini kurarız.', 'Hmm, bu parça oraya uymadı.', 'Yanlış düğme! Bir daha.'],
      intro: ['Bak ne keşfettim:', 'Şunu bir kurcalayalım:', 'Merak ettim, baktım:'],
      poke: ['Dur dur, deney bozulacak!', 'Sekiz kolum da dolu. Dokuzuncusu sen ol!', 'Aa! Aklıma yeni bir fikir geldi!'],
      finish: 'Deney tamam! Sonuç: öğrendin.',
      perfect: 'Sıfır hata! Bu formülü saklayalım.',
      fail: 'Laboratuvar biraz dağıldı. Toparlayıp baştan?',
    ),
    en: Voice(
      species: 'Octopus',
      trait: 'Curious inventor',
      bio: 'Tinkers with everything and keeps eight arms on eight jobs. Adores matching and ordering puzzles.',
      greet: 'Ooh, you’re here! I prepared eight things with my eight arms!',
      praise: ['You found it!', 'The pieces clicked!', 'Experiment successful!', 'I’m applauding with all eight arms!'],
      oops: ['The experiment blew up! No problem, we’ll build another.', 'Hmm, that piece didn’t fit there.', 'Wrong button! Again.'],
      intro: ['Look what I discovered:', 'Let’s poke at this:', 'I got curious and checked:'],
      poke: ['Careful, you’ll spoil the experiment!', 'All eight arms are busy. Be my ninth!', 'Oh! I just had a new idea!'],
      finish: 'Experiment complete! Result: you learned.',
      perfect: 'Zero mistakes! Let’s keep this formula.',
      fail: 'The lab’s a bit of a mess. Tidy up and start over?',
    ),
  ),
  Character(
    id: MascotId.dalga,
    name: 'Dalga',
    color: 0xFF2380C4,
    tr: Voice(
      species: 'Yunus',
      trait: 'Enerjik amigo',
      bio: 'Coşkuludur, yerinde duramaz. Serini en çok o takip eder; bir gün aksatırsan ilk o fark eder.',
      greet: 'Hey hey! Bugün de seriyi uçuruyoruz!',
      praise: ['Süpersin!', 'Dalga gibi geliyorsun!', 'İşte bu tempo!', 'Bir tane daha, hadi!'],
      oops: ['Sorun yok, dalga yine gelir!', 'Düştün mü? Kalk, devam!', 'O ısınma turuydu!'],
      intro: ['Hızlı bir bilgi:', 'Şunu kap, yüzmeye devam:', 'Antrenman notu:'],
      poke: ['Hazırım! Hadi bir ders daha!', 'Çak bir beşlik!', 'Durmak yok, seri bozulmasın!'],
      finish: 'Bitiş çizgisi! Harika yüzdün!',
      perfect: 'Kusursuz parkur! Altın madalya senin!',
      fail: 'Nefesin tükendi. Biraz dinlen, yine dalarız!',
    ),
    en: Voice(
      species: 'Dolphin',
      trait: 'Energetic cheerleader',
      bio: 'Bubbly and can’t sit still. Watches your streak more closely than anyone; skip a day and they’re the first to notice.',
      greet: 'Hey hey! We’re riding the streak again today!',
      praise: ['You’re amazing!', 'You’re coming in like a wave!', 'That’s the pace!', 'One more, come on!'],
      oops: ['No worries, the wave comes back!', 'Fell off? Up you get!', 'That was the warm-up lap!'],
      intro: ['Quick fact:', 'Grab this and keep swimming:', 'Training note:'],
      poke: ['I’m ready! One more lesson!', 'High five!', 'No stopping, keep the streak alive!'],
      finish: 'Finish line! Great swim!',
      perfect: 'A flawless run! The gold medal is yours!',
      fail: 'You’re out of breath. Rest a bit and we’ll dive again!',
    ),
  ),
];

Character characterOf(MascotId id) => cast.firstWhere((c) => c.id == id);

/// Üniteleri sırayla farklı karakterler sunar; ilk üniteyi yol arkadaşın alır.
Character hostOfUnit(int unitIndex, MascotId companion) {
  final start = cast.indexWhere((c) => c.id == companion);
  return cast[(start + unitIndex) % cast.length];
}
