import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

String fa(String s) {
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const pe = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  var r = s;
  for (int i = 0; i < 10; i++) {
    r = r.replaceAll(en[i], pe[i]);
  }
  return r;
}

const monthNames = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
];
const weekDays = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];

class Task {
  final String id;
  final String dayKey;
  final String title;
  final int startMinutes;
  final int duration;

  Task({
    required this.id,
    required this.dayKey,
    required this.title,
    required this.startMinutes,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': dayKey,
        'title': title,
        'start': startMinutes,
        'dur': duration,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        dayKey: j['day'] as String,
        title: j['title'] as String,
        startMinutes: j['start'] as int,
        duration: j['dur'] as int,
      );

  String get startLabel =>
      '${(startMinutes ~/ 60).toString().padLeft(2, '0')}:${(startMinutes % 60).toString().padLeft(2, '0')}';

  String get endLabel {
    final e = (startMinutes + duration) % (24 * 60);
    return '${(e ~/ 60).toString().padLeft(2, '0')}:${(e % 60).toString().padLeft(2, '0')}';
  }

  String get durationLabel =>
      duration == 30 ? '۳۰ دقیقه' : duration == 60 ? '۱ ساعت' : '۲ ساعت';

  int get notifyBase => id.hashCode.abs() % 500000;
}

class Store {
  static final List<Task> tasks = [];
  static const _key = 'amir_flow_tasks_v1';

  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null) return;
    final list = jsonDecode(raw) as List;
    tasks
      ..clear()
      ..addAll(list.map((e) => Task.fromJson(e as Map<String, dynamic>)));
  }

  static Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        _key, jsonEncode(tasks.map((e) => e.toJson()).toList()));
  }

  static int countFor(String dayKey) =>
      tasks.where((t) => t.dayKey == dayKey).length;
}

class Notify {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'amir_flow_channel';

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tehran'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await impl?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      'یادآور برنامه‌ها',
      description: 'اعلان شروع و پایان پارت‌های برنامه‌ریزی',
      importance: Importance.max,
    ));
    await impl?.requestNotificationsPermission();
    await impl?.requestExactAlarmsPermission();
  }

  static Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!when.isAfter(DateTime.now())) return;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'یادآور برنامه‌ها',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime, // این خط اضافه شد
    );
  }

  static Future<void> cancel(int id) => _plugin.cancel(id);
}

Future<void> scheduleTask(Task t) async {
  final p = t.dayKey.split('/').map(int.parse).toList();
  final g = Jalali(p[0], p[1], p[2]).toGregorian();
  final start =
      DateTime(g.year, g.month, g.day, t.startMinutes ~/ 60, t.startMinutes % 60);
  final end = start.add(Duration(minutes: t.duration));

  await Notify.schedule(
    id: t.notifyBase * 2,
    title: 'شروع: ${t.title}',
    body: 'پارت ${t.durationLabel} شروع شد، بریم!',
    when: start,
  );
  await Notify.schedule(
    id: t.notifyBase * 2 + 1,
    title: 'پایان: ${t.title}',
    body: 'آفرین! پارت تموم شد ✅',
    when: end,
  );
}

Future<void> cancelTask(Task t) async {
  await Notify.cancel(t.notifyBase * 2);
  await Notify.cancel(t.notifyBase * 2 + 1);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notify.init();
  await Store.load();
  runApp(const AmirFlowApp());
}

class AmirFlowApp extends StatelessWidget {
  const AmirFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amir Flow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF12121A),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const CalendarScreen(),
    );
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = Jalali.now();
    _year = now.year;
    _month = now.month;
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year--;
      } else {
        _month--;
      }
    });
  }

  void _nextMonth() {
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year++;
      } else {
        _month++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF9C8CFF), size: 20),
            const SizedBox(width: 8),
            Text('Amir Flow',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white.withOpacity(0.95))),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildMonthHeader(),
          _buildWeekRow(),
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2A),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _nextMonth,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'ماه بعد',
          ),
          Column(
            children: [
              Text('${monthNames[_month - 1]} ${fa(_year.toString())}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('تقویم شمسی',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.5))),
            ],
          ),
          IconButton(
            onPressed: _prevMonth,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'ماه قبل',
          ),
        ],
      ),
    );
  }

  Widget _buildWeekRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: weekDays
            .map((d) => Expanded(
                  child: Center(
                    child: Text(d,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.45))),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildGrid() {
    final first = Jalali(_year, _month, 1);
    final offset = first.weekDay - 1;
    final len = first.monthLength;
    final cells = ((offset + len) / 7).ceil() * 7;
    final today = Jalali.now();

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: cells,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (context, i) {
        final dayNum = i - offset + 1;
        if (dayNum < 1 || dayNum > len) return const SizedBox.shrink();

        final key = '$_year/$_month/$dayNum';
        final count = Store.countFor(key);
        final isToday =
            today.year == _year && today.month == _month && today.day == dayNum;

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      DayScreen(jy: _year, jm: _month, jd: dayNum)),
            );
            setState(() {});
          },
          child: Container(
            decoration: BoxDecoration(
              color: isToday
                  ? const Color(0xFF6C5CE7)
                  : const Color(0xFF1C1C26),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isToday
                    ? const Color(0xFF9C8CFF)
                    : Colors.white.withOpacity(0.05),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(fa(dayNum.toString()),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday
                            ? Colors.white
                            : Colors.white.withOpacity(0.85))),
                const SizedBox(height: 3),
                if (count > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isToday
                          ? Colors.white.withOpacity(0.28)
                          : const Color(0xFF6C5CE7).withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(fa(count.toString()),
                        style: const TextStyle(fontSize: 9)),
                  )
              ],
            ),
          ),
        );
      },
    );
  }
}

class DayScreen extends StatefulWidget {
  final int jy, jm, jd;
  const DayScreen(
      {super.key, required this.jy, required this.jm, required this.jd});

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  String get dayKey => '${widget.jy}/${widget.jm}/${widget.jd}';

  List<Task> get dayTasks =>
      Store.tasks.where((t) => t.dayKey == dayKey).toList()
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

  Future<void> _addTask() async {
    final titleCtrl = TextEditingController();
    int duration = 60;
    final now = TimeOfDay.now();
    TimeOfDay start = TimeOfDay(hour: now.hour, minute: (now.minute ~/ 5) * 5);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A25),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('برنامه جدید',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'عنوان کار',
                    hintText: 'مثلاً: مطالعه کتاب',
                    filled: true,
                    fillColor: const Color(0xFF23232F),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('شروع: '),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: start,
                          initialEntryMode: TimePickerEntryMode.input,
                        );
                        if (picked != null) {
                          setSheet(() => start = picked);
                        }
                      },
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(fa(
                          '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('مدت پارت'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final d in [30, 60, 120])
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(d == 30
                              ? '۳۰ دقیقه'
                              : d == 60
                                  ? '۱ ساعت'
                                  : '۲ ساعت'),
                          selected: duration == d,
                          onSelected: (_) => setSheet(() => duration = d),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF6C5CE7)),
                  onPressed: () async {
                    final t = Task(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      dayKey: dayKey,
                      title: titleCtrl.text.trim().isEmpty
                          ? 'برنامه بدون عنوان'
                          : titleCtrl.text.trim(),
                      startMinutes: start.hour * 60 + start.minute,
                      duration: duration,
                    );
                    Store.tasks.add(t);
                    await Store.save();
                    await scheduleTask(t);
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() {});
                  },
                  child: const Text('ذخیره و یادآوری'),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = dayTasks;
    final j = Jalali(widget.jy, widget.jm, widget.jd);
    final g = j.toGregorian();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${weekDays[(j.weekDay - 1) % 7]}  ${fa(widget.jd.toString())} ${monthNames[widget.jm - 1]}',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            Text(fa('${widget.jy}  |  ${g.year}-${g.month}-${g.day}'),
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.5))),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTask,
        backgroundColor: const Color(0xFF6C5CE7),
        icon: const Icon(Icons.add),
        label: const Text('برنامه جدید'),
      ),
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_note,
                      size: 64,
                      color: Colors.white.withOpacity(0.15)),
                  const SizedBox(height: 12),
                  Text('برای این روز برنامه‌ای نداری',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5))),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: tasks.length,
              itemBuilder: (context, i) {
                final t = tasks[i];
                return Dismissible(
                  key: ValueKey(t.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 24),
                    child: const Icon(Icons.delete),
                  ),
                  onDismissed: (_) async {
                    await cancelTask(t);
                    Store.tasks.removeWhere((x) => x.id == t.id);
                    await Store.save();
                    setState(() {});
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C26),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C5CE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                fa('${t.startLabel} تا ${t.endLabel}  •  ${t.durationLabel}'),
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Colors.white.withOpacity(0.5)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.notifications_active,
                              size: 20,
                              color: const Color(0xFF9C8CFF)
                                  .withOpacity(0.9)),
                          tooltip: 'یادآوری مجدد',
                          onPressed: () async {
                            await scheduleTask(t);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'یادآورها دوباره تنظیم شدند ✅')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
