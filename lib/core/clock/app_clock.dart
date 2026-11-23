abstract class AppClock {
  const AppClock();
  DateTime now();

  String todayLocalDate() => formatLocalDate(now());

  static String formatLocalDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class SystemAppClock extends AppClock {
  const SystemAppClock();

  @override
  DateTime now() => DateTime.now();
}

class FixedAppClock extends AppClock {
  DateTime current;
  FixedAppClock(this.current);

  @override
  DateTime now() => current;
}
