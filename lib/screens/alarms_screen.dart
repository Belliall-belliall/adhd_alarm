import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../services/firestore_service.dart';

// Globalny obiekt powiadomień – inicjalizowany w main.dart
final FlutterLocalNotificationsPlugin globalNotifications =
    FlutterLocalNotificationsPlugin();

class AlarmsScreen extends StatefulWidget {
  const AlarmsScreen({super.key});

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends State<AlarmsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  int _alarmNotifId(String id) =>
      id.codeUnits.fold(0, (prev, e) => prev + e) % 90000;

  int _checkNotifId(String id) =>
      (id.codeUnits.fold(0, (prev, e) => prev + e) % 90000) + 90000;

  Future<void> _scheduleAlarm(
      String id, String time, String label, String checkTime) async {
    try {
      final parts = time.split(':');
      if (parts.length != 2) return;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return;

      final location = tz.getLocation('Europe/Warsaw');
      final now = tz.TZDateTime.now(location);
      var scheduledDate = tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await globalNotifications.zonedSchedule(
        _alarmNotifId(id),
        'Budzik: $label',
        'Czas na: $label',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'alarm_channel',
            'Budziki',
            channelDescription: 'Powiadomienia budzika',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      int checkMinutes = 30;
      if (checkTime == '1 godz.') checkMinutes = 60;
      if (checkTime == '2 godz.') checkMinutes = 120;

      final checkDate = scheduledDate.add(Duration(minutes: checkMinutes));

      await globalNotifications.zonedSchedule(
        _checkNotifId(id),
        'Przypomnienie kontrolne',
        'Czy wykonałaś: $label?',
        checkDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'check_channel',
            'Przypomnienia kontrolne',
            channelDescription: 'Powiadomienia kontrolne',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Błąd planowania alarmu: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nie udało się zaplanować budzika.')),
        );
      }
    }
  }

  Future<void> _cancelAlarm(String id) async {
    try {
      await globalNotifications.cancel(_alarmNotifId(id));
      await globalNotifications.cancel(_checkNotifId(id));
    } catch (e) {
      debugPrint('Błąd anulowania alarmu: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _firestoreService.getAlarms(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Błąd ładowania budzików.'),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyState();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) =>
                        _buildAlarmCard(snapshot.data![index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAlarmDialog,
        backgroundColor: const Color(0xFF2B6CB0),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nowy budzik',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2B6CB0), Color(0xFF2C7A4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '⏰ Budziki',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Dotknij + aby dodać, przytrzymaj aby edytować',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.alarm, size: 64, color: Color(0xFFA0AEC0)),
          SizedBox(height: 16),
          Text(
            'Brak budzików',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A5568),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Dodaj pierwszy budzik\nklikając przycisk poniżej',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF718096)),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmCard(Map<String, dynamic> alarm) {
    bool isActive = alarm['active'] as bool;
    return GestureDetector(
      onLongPress: () => _showAlarmOptions(alarm),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: isActive
                  ? const Color(0xFF2B6CB0)
                  : const Color(0xFFCBD5E0),
              width: 4,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alarm['time'],
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? const Color(0xFF2B6CB0)
                          : const Color(0xFFA0AEC0),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alarm['label'],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? const Color(0xFF2D3748)
                          : const Color(0xFFA0AEC0),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.notifications_outlined,
                        size: 14,
                        color: isActive
                            ? const Color(0xFF718096)
                            : const Color(0xFFCBD5E0),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Kontrolne po ${alarm['checkTime']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isActive
                              ? const Color(0xFF718096)
                              : const Color(0xFFCBD5E0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Switch(
                  value: isActive,
                  onChanged: (val) async {
                    await _firestoreService.toggleAlarm(alarm['id'], val);
                    if (val) {
                      await _scheduleAlarm(alarm['id'], alarm['time'],
                          alarm['label'], alarm['checkTime']);
                    } else {
                      await _cancelAlarm(alarm['id']);
                    }
                  },
                  activeColor: const Color(0xFF2B6CB0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Menu opcji budzika – edytuj lub usuń
  void _showAlarmOptions(Map<String, dynamic> alarm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Text(
                    alarm['time'],
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2B6CB0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    alarm['label'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading:
                  const Icon(Icons.edit_outlined, color: Color(0xFF2B6CB0)),
              title: const Text('Edytuj budzik'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditAlarmDialog(alarm);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Usuń budzik',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(alarm['id']);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Okienko edycji budzika
  void _showEditAlarmDialog(Map<String, dynamic> alarm) {
    final parts = (alarm['time'] as String).split(':');
    TimeOfDay selectedTime = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
    String selectedCheckTime = alarm['checkTime'] as String;
    final labelController =
        TextEditingController(text: alarm['label'] as String);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edytuj budzik',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Godzina',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF718096))),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: selectedTime,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setModalState(() => selectedTime = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time,
                          color: Color(0xFF2B6CB0)),
                      const SizedBox(width: 12),
                      Text(
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B6CB0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Nazwa / opis',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF718096))),
              const SizedBox(height: 8),
              TextField(
                controller: labelController,
                maxLength: 50,
                decoration: InputDecoration(
                  hintText: 'np. Leki poranne...',
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFF0F4F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFFCBD5E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFFCBD5E0)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Powiadomienie kontrolne po',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF718096))),
              const SizedBox(height: 8),
              Row(
                children:
                    ['30 min', '1 godz.', '2 godz.'].map((option) {
                  bool selected = selectedCheckTime == option;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setModalState(
                          () => selectedCheckTime = option),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF2B6CB0)
                              : const Color(0xFFF0F4F8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF2B6CB0)
                                : const Color(0xFFCBD5E0),
                          ),
                        ),
                        child: Text(
                          option,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF4A5568),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final label = labelController.text.trim().isEmpty
                        ? 'Budzik'
                        : labelController.text.trim();
                    final time =
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                    Navigator.of(ctx, rootNavigator: true).pop();

                    // Anuluj stary alarm
                    await _cancelAlarm(alarm['id']);

                    // Zaktualizuj w Firebase
                    await _firestoreService.updateAlarm(
                        alarm['id'], time, label, selectedCheckTime);

                    // Zaplanuj nowy alarm
                    await _scheduleAlarm(
                        alarm['id'], time, label, selectedCheckTime);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B6CB0),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Zapisz zmiany',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddAlarmDialog() {
    TimeOfDay selectedTime = TimeOfDay.now();
    String selectedCheckTime = '30 min';
    final labelController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nowy budzik',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Godzina',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF718096))),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: selectedTime,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setModalState(() => selectedTime = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time,
                          color: Color(0xFF2B6CB0)),
                      const SizedBox(width: 12),
                      Text(
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B6CB0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Nazwa / opis',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF718096))),
              const SizedBox(height: 8),
              TextField(
                controller: labelController,
                maxLength: 50,
                decoration: InputDecoration(
                  hintText: 'np. Leki poranne...',
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFF0F4F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFFCBD5E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFFCBD5E0)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Powiadomienie kontrolne po',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF718096))),
              const SizedBox(height: 8),
              Row(
                children:
                    ['30 min', '1 godz.', '2 godz.'].map((option) {
                  bool selected = selectedCheckTime == option;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setModalState(
                          () => selectedCheckTime = option),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF2B6CB0)
                              : const Color(0xFFF0F4F8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF2B6CB0)
                                : const Color(0xFFCBD5E0),
                          ),
                        ),
                        child: Text(
                          option,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF4A5568),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final label = labelController.text.trim().isEmpty
                        ? 'Budzik'
                        : labelController.text.trim();
                    final time =
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                    Navigator.of(ctx, rootNavigator: true).pop();
                    final id = await _firestoreService.addAlarm(
                        time, label, selectedCheckTime);
                    if (id.isNotEmpty) {
                      await _scheduleAlarm(
                          id, time, label, selectedCheckTime);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B6CB0),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Zapisz budzik',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usuń budzik'),
        content: const Text('Czy na pewno chcesz usunąć ten budzik?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _cancelAlarm(id);
              _firestoreService.deleteAlarm(id);
            },
            child: const Text('Usuń',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}