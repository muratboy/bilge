/// Grafik fonksiyonları için küçük ve güvenli bir ifade çözümleyici.
/// Kurs içeriği dışarıdan geldiği için hiçbir şey çalıştırılmaz: yalnızca sayılar, x, + − * / ^,
/// parantez ve bilinen birkaç fonksiyon (sin, cos, tan, sqrt, abs, ln, log, exp) tanınır.
library;

import 'dart:math' as math;

typedef Fn = double Function(double x);

const _functions = <String, double Function(double)>{
  'sin': math.sin,
  'cos': math.cos,
  'tan': math.tan,
  'sqrt': math.sqrt,
  'abs': _abs,
  'ln': math.log,
  'log': _log10,
  'exp': math.exp,
};

double _abs(double v) => v.abs();
double _log10(double v) => math.log(v) / math.ln10;

class _Parser {
  _Parser(this.s);
  final String s;
  int i = 0;

  bool get done => i >= s.length;
  String get peek => done ? '' : s[i];
  bool eat(String c) {
    if (peek != c) return false;
    i++;
    return true;
  }

  Fn expr() {
    var left = term();
    while (true) {
      if (eat('+')) {
        final a = left, b = term();
        left = (x) => a(x) + b(x);
      } else if (eat('-')) {
        final a = left, b = term();
        left = (x) => a(x) - b(x);
      } else {
        return left;
      }
    }
  }

  Fn term() {
    var left = unary();
    while (true) {
      if (eat('*')) {
        final a = left, b = unary();
        left = (x) => a(x) * b(x);
      } else if (eat('/')) {
        final a = left, b = unary();
        left = (x) => a(x) / b(x);
      } else if (!done && RegExp(r'[0-9.a-zπ(]').hasMatch(peek)) {
        // Yazılmamış çarpma: 2x, 3(x+1), (x+1)(x-1), 2sin(x)
        final a = left, b = power();
        left = (x) => a(x) * b(x);
      } else {
        return left;
      }
    }
  }

  Fn unary() {
    if (eat('-')) {
      final a = unary();
      return (x) => -a(x);
    }
    if (eat('+')) return unary();
    return power();
  }

  Fn power() {
    final base = primary();
    if (!eat('^')) return base;
    final exponent = unary(); // sağdan birleşir: 2^3^2 = 2^(3^2)
    return (x) => math.pow(base(x), exponent(x)).toDouble();
  }

  Fn primary() {
    if (eat('(')) {
      final inner = expr();
      if (!eat(')')) throw const FormatException(')');
      return inner;
    }
    if (eat('|')) {
      final inner = expr();
      if (!eat('|')) throw const FormatException('|');
      return (x) => inner(x).abs();
    }
    final number = RegExp(r'\d+\.?\d*|\.\d+').matchAsPrefix(s, i);
    if (number != null) {
      i = number.end;
      final v = double.parse(number[0]!);
      return (_) => v;
    }
    final word = RegExp('[a-zπ]+').matchAsPrefix(s, i)?[0] ?? '';
    for (final name in _functions.keys) {
      if (word.startsWith(name) && s.startsWith('(', i + name.length)) {
        i += name.length + 1;
        final arg = expr();
        if (!eat(')')) throw const FormatException(')');
        final f = _functions[name]!;
        return (x) => f(arg(x));
      }
    }
    if (word.startsWith('pi')) {
      i += 2;
      return (_) => math.pi;
    }
    if (eat('π')) return (_) => math.pi;
    if (eat('x')) return (x) => x;
    if (eat('e')) return (_) => math.e;
    throw FormatException(done ? 'eksik ifade' : peek);
  }
}

/// "x^2-3", "2x+1", "sin(x)/x" gibi bir ifadeyi fonksiyona çevirir; anlaşılmıyorsa null döner.
Fn? parseFunction(String source) {
  var s = source.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  s = s.replaceFirst(RegExp(r'^(?:y|f\(x\))='), '');
  s = s
      .replaceAll('**', '^')
      .replaceAll(RegExp('[×·⋅]'), '*')
      .replaceAll('÷', '/')
      .replaceAll(RegExp('[−–]'), '-')
      .replaceAll('²', '^2')
      .replaceAll('³', '^3')
      .replaceAllMapped(RegExp(r'√(\(|[0-9.x]+)'), (m) => m[1] == '(' ? 'sqrt(' : 'sqrt(${m[1]})')
      .replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
  if (s.isEmpty || s.length > 80) return null;
  try {
    final p = _Parser(s);
    final f = p.expr();
    return p.done ? f : null;
  } on FormatException {
    return null;
  }
}
