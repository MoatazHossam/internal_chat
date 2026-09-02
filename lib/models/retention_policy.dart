class DeviceRetentionPolicy {
  static const maximumUserDays = 365;
  const DeviceRetentionPolicy({required this.administratorMaximumDays, required this.userSelectedDays}) : assert(administratorMaximumDays > 0 && administratorMaximumDays <= maximumUserDays), assert(userSelectedDays > 0 && userSelectedDays <= administratorMaximumDays);
  final int administratorMaximumDays;
  final int userSelectedDays;
  Duration get retentionPeriod => Duration(days: userSelectedDays);
}
