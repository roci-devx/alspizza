import 'package:intl/intl.dart';

final _money = NumberFormat.simpleCurrency(locale: 'en_US');
final _compact = NumberFormat.compactSimpleCurrency(locale: 'en_US');
final _time = DateFormat('h:mm a');
final _day = DateFormat('EEE, MMM d');

String money(num cents) => _money.format(cents / 100);

/// $1.2K / $48.3K style for stat tiles.
String moneyCompact(num cents) => cents.abs() >= 100000 ? _compact.format(cents / 100) : money(cents);

String compactNumber(num n) => NumberFormat.compact(locale: 'en_US').format(n);

String clock(DateTime t) => _time.format(t.toLocal());

String dayLabel(DateTime t) => _day.format(t.toLocal());

String minutesLabel(int minutes) => minutes < 60 ? '$minutes min' : '${minutes ~/ 60} hr ${minutes % 60} min';

/// "5 min ago", "2 hr ago", "Oct 12".
String ago(DateTime t) {
  final d = DateTime.now().difference(t.toLocal());
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr ago';
  return DateFormat('MMM d').format(t.toLocal());
}

String percent(double v, {int digits = 0}) => '${(v * 100).toStringAsFixed(digits)}%';

DateTime? parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v as String);

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String prettyPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  final ten = digits.length == 11 && digits.startsWith('1') ? digits.substring(1) : digits;
  if (ten.length != 10) return phone;
  return '(${ten.substring(0, 3)}) ${ten.substring(3, 6)}-${ten.substring(6)}';
}
