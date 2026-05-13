class TimeFormat {
  TimeFormat._();

  /// 聊天消息时间格式
  static String chatTime(DateTime dt, {DateTime? previousDt}) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;

    if (isToday) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    final isThisYear = dt.year == now.year;
    if (isThisYear) {
      return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// 是否需要显示时间分隔线（与前一条消息间隔超过 30 分钟）
  static bool shouldShowTimeGap(DateTime current, DateTime? previous) {
    if (previous == null) return false;
    return current.difference(previous).inMinutes > 30;
  }
}
