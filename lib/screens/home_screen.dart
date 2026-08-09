import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../services/firestore_service.dart';
import 'alarms_screen.dart';
import 'recordings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _firestoreService.initializeDefaultTasks();
    _firestoreService.checkAndResetDailyTasks();
  }

  Future<void> _scheduleTaskNotification(
      String id, String name, String time, int? repeatMinutes) async {
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

      final notifId =
          ('task_$id').codeUnits.fold(0, (prev, e) => prev + e) % 80000;

      await globalNotifications.zonedSchedule(
        notifId,
        'Przypomnienie o zadaniu',
        name,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_channel',
            'Zadania',
            channelDescription: 'Przypomnienia o zadaniach',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      if (repeatMinutes != null) {
        for (int i = 1; i <= 3; i++) {
          final repeatDate =
              scheduledDate.add(Duration(minutes: repeatMinutes * i));
          await globalNotifications.zonedSchedule(
            notifId + i,
            'Powtórzenie przypomnienia',
            name,
            repeatDate,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'task_channel',
                'Zadania',
                channelDescription: 'Przypomnienia o zadaniach',
                importance: Importance.high,
                priority: Priority.high,
                playSound: true,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    } catch (e) {
      debugPrint('Błąd planowania powiadomienia zadania: $e');
    }
  }

  Future<void> _cancelTaskNotification(String id) async {
    try {
      final notifId =
          ('task_$id').codeUnits.fold(0, (prev, e) => prev + e) % 80000;
      await globalNotifications.cancel(notifId);
      for (int i = 1; i <= 3; i++) {
        await globalNotifications.cancel(notifId + i);
      }
    } catch (e) {
      debugPrint('Błąd anulowania powiadomienia zadania: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProgressSection(),
                        _buildSectionLabelWithAction(
                          '📌 Codzienne',
                          Icons.add,
                          _showManageDailyTasksDialog,
                        ),
                        _buildDailyTasksList(),
                        const SizedBox(height: 20),
                        _buildSectionLabel('📋 Dodatkowe'),
                        _buildExtraTasksList(),
                        _buildAddButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const AlarmsScreen(),
          const RecordingsScreen(),
          const SizedBox(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
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
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dzień dobry 👋',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getTodayDate(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Text('🔔', style: TextStyle(fontSize: 28)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white30),
            ),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _firestoreService.getDailyTasks(),
              builder: (context, snapshot) {
                String? nextReminder;

                if (snapshot.hasData) {
                  final now = TimeOfDay.now();
                  final tasks = snapshot.data!
                      .where((t) =>
                          t['time'] != null && t['done'] == false)
                      .toList();

                  tasks.sort((a, b) {
                    final aParts = (a['time'] as String).split(':');
                    final bParts = (b['time'] as String).split(':');
                    final aMinutes = int.parse(aParts[0]) * 60 +
                        int.parse(aParts[1]);
                    final bMinutes = int.parse(bParts[0]) * 60 +
                        int.parse(bParts[1]);
                    return aMinutes.compareTo(bMinutes);
                  });

                  final nowMinutes = now.hour * 60 + now.minute;

                  for (final task in tasks) {
                    final parts = (task['time'] as String).split(':');
                    final taskMinutes =
                        int.parse(parts[0]) * 60 + int.parse(parts[1]);
                    if (taskMinutes > nowMinutes) {
                      nextReminder =
                          '${task['time']} – ${task['name']}';
                      break;
                    }
                  }

                  if (nextReminder == null && tasks.isNotEmpty) {
                    nextReminder =
                        '${tasks.first['time']} – ${tasks.first['name']}';
                  }
                }

                if (nextReminder == null) return const SizedBox.shrink();

                return Row(
                  children: [
                    const Text('⏰', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    const Text(
                      'Następne: ',
                      style:
                          TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    Expanded(
                      child: Text(
                        nextReminder!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestoreService.getDailyTasks(),
      builder: (context, snapshot) {
        int done = 0;
        int total = 0;
        if (snapshot.hasData) {
          total = snapshot.data!.length;
          done = snapshot.data!.where((t) => t['done'] == true).length;
        }
        double progress = total > 0 ? done / total : 0;

        return Container(
          margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dzisiejszy postęp',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4A5568),
                    ),
                  ),
                  Text(
                    '$done z $total zadań',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2B6CB0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF2B6CB0),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDailyTasksList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestoreService.getDailyTasks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Brak zadań codziennych'),
          );
        }
        return Column(
          children: snapshot.data!
              .map((task) => _buildTaskCard(task, true))
              .toList(),
        );
      },
    );
  }

  Widget _buildExtraTasksList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _firestoreService.getExtraTasks(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          children: snapshot.data!
              .map((task) => _buildTaskCard(task, false))
              .toList(),
        );
      },
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Color(0xFF718096),
        ),
      ),
    );
  }

  Widget _buildSectionLabelWithAction(
      String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Color(0xFF718096),
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Icon(icon, size: 18, color: const Color(0xFF718096)),
          ),
        ],
      ),
    );
  }

  // Wspólna logika dla okienka dodawania i edycji zadania
  Widget _buildTaskForm({
    required TextEditingController nameController,
    required TimeOfDay? selectedTime,
    required bool hasReminder,
    required bool isRepeating,
    required int selectedRepeatMinutes,
    required void Function(void Function()) setDialogState,
    required void Function(TimeOfDay?) onTimePicked,
  }) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: 'Nazwa zadania...',
              labelText: 'Nazwa',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Switch(
                value: hasReminder,
                onChanged: (val) {
                  setDialogState(() {});
                },
                activeColor: const Color(0xFF2B6CB0),
              ),
              const SizedBox(width: 8),
              const Text(
                'Dodaj przypomnienie',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (hasReminder) ...[
            const SizedBox(height: 12),
            const Text(
              'Godzina przypomnienia',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF718096),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: selectedTime ?? TimeOfDay.now(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  ),
                );
                if (picked != null) onTimePicked(picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time,
                        color: Color(0xFF2B6CB0), size: 20),
                    const SizedBox(width: 10),
                    Text(
                      selectedTime != null
                          ? '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'
                          : 'Wybierz godzinę...',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: selectedTime != null
                            ? const Color(0xFF2B6CB0)
                            : const Color(0xFFA0AEC0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Typ powiadomienia',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF718096),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setDialogState(() {}),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !isRepeating
                            ? const Color(0xFF2B6CB0)
                            : const Color(0xFFF0F4F8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: !isRepeating
                              ? const Color(0xFF2B6CB0)
                              : const Color(0xFFCBD5E0),
                        ),
                      ),
                      child: Text(
                        'Jednorazowe',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: !isRepeating
                              ? Colors.white
                              : const Color(0xFF4A5568),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setDialogState(() {}),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isRepeating
                            ? const Color(0xFF2B6CB0)
                            : const Color(0xFFF0F4F8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isRepeating
                              ? const Color(0xFF2B6CB0)
                              : const Color(0xFFCBD5E0),
                        ),
                      ),
                      child: Text(
                        'Powtarzające',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isRepeating
                              ? Colors.white
                              : const Color(0xFF4A5568),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (isRepeating) ...[
              const SizedBox(height: 12),
              const Text(
                'Powtarzaj co',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF718096),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [10, 15, 30].map((mins) {
                  bool selected = selectedRepeatMinutes == mins;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() {}),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF2C7A4B)
                              : const Color(0xFFF0F4F8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF2C7A4B)
                                : const Color(0xFFCBD5E0),
                          ),
                        ),
                        child: Text(
                          '$mins min',
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
            ],
          ],
        ],
      ),
    );
  }

  void _showManageDailyTasksDialog() {
    final nameController = TextEditingController();
    TimeOfDay? selectedTime;
    bool hasReminder = false;
    bool isRepeating = false;
    int selectedRepeatMinutes = 10;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nowe zadanie codzienne'),
          content: StatefulBuilder(
            builder: (ctx2, setInnerState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        hintText: 'Nazwa zadania...',
                        labelText: 'Nazwa',
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Switch(
                          value: hasReminder,
                          onChanged: (val) {
                            setDialogState(() {
                              hasReminder = val;
                              if (!val) {
                                selectedTime = null;
                                isRepeating = false;
                              }
                            });
                          },
                          activeColor: const Color(0xFF2B6CB0),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Dodaj przypomnienie',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (hasReminder) ...[
                      const SizedBox(height: 12),
                      const Text('Godzina przypomnienia',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF718096),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime:
                                selectedTime ?? TimeOfDay.now(),
                            builder: (context, child) => MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                  alwaysUse24HourFormat: true),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedTime = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4F8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFFCBD5E0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time,
                                  color: Color(0xFF2B6CB0), size: 20),
                              const SizedBox(width: 10),
                              Text(
                                selectedTime != null
                                    ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                                    : 'Wybierz godzinę...',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: selectedTime != null
                                      ? const Color(0xFF2B6CB0)
                                      : const Color(0xFFA0AEC0),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Typ powiadomienia',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF718096),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(
                                  () => isRepeating = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10),
                                decoration: BoxDecoration(
                                  color: !isRepeating
                                      ? const Color(0xFF2B6CB0)
                                      : const Color(0xFFF0F4F8),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                    color: !isRepeating
                                        ? const Color(0xFF2B6CB0)
                                        : const Color(0xFFCBD5E0),
                                  ),
                                ),
                                child: Text(
                                  'Jednorazowe',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: !isRepeating
                                        ? Colors.white
                                        : const Color(0xFF4A5568),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(
                                  () => isRepeating = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10),
                                decoration: BoxDecoration(
                                  color: isRepeating
                                      ? const Color(0xFF2B6CB0)
                                      : const Color(0xFFF0F4F8),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isRepeating
                                        ? const Color(0xFF2B6CB0)
                                        : const Color(0xFFCBD5E0),
                                  ),
                                ),
                                child: Text(
                                  'Powtarzające',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isRepeating
                                        ? Colors.white
                                        : const Color(0xFF4A5568),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isRepeating) ...[
                        const SizedBox(height: 12),
                        const Text('Powtarzaj co',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF718096),
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Row(
                          children: [10, 15, 30].map((mins) {
                            bool selected =
                                selectedRepeatMinutes == mins;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => setDialogState(() =>
                                    selectedRepeatMinutes = mins),
                                child: Container(
                                  margin:
                                      const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF2C7A4B)
                                        : const Color(0xFFF0F4F8),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFF2C7A4B)
                                          : const Color(0xFFCBD5E0),
                                    ),
                                  ),
                                  child: Text(
                                    '$mins min',
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
                      ],
                    ],
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anuluj'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final name = nameController.text.trim();
                final time = selectedTime != null
                    ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                    : null;
                final repeat =
                    hasReminder && isRepeating ? selectedRepeatMinutes : null;
                Navigator.pop(ctx);
                final id =
                    await _firestoreService.addDailyTaskWithReminder(
                        name, time, repeat);
                if (hasReminder && selectedTime != null && id.isNotEmpty) {
                  await _scheduleTaskNotification(id, name, time!, repeat);
                }
              },
              child: const Text('Dodaj'),
            ),
          ],
        ),
      ),
    );
  }

  // Okienko EDYCJI zadania codziennego
  void _showEditDailyTaskDialog(Map<String, dynamic> task) {
    final nameController = TextEditingController(text: task['name']);
    TimeOfDay? selectedTime;
    bool hasReminder = false;
    bool isRepeating = false;
    int selectedRepeatMinutes = 10;

    // Wypełnij aktualnymi danymi
    if (task['time'] != null) {
      final parts = (task['time'] as String).split(':');
      selectedTime = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
      hasReminder = true;
    }
    if (task['repeatMinutes'] != null) {
      isRepeating = true;
      selectedRepeatMinutes = task['repeatMinutes'] as int;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edytuj zadanie'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Nazwa zadania...',
                    labelText: 'Nazwa',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Switch(
                      value: hasReminder,
                      onChanged: (val) {
                        setDialogState(() {
                          hasReminder = val;
                          if (!val) {
                            selectedTime = null;
                            isRepeating = false;
                          }
                        });
                      },
                      activeColor: const Color(0xFF2B6CB0),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Przypomnienie',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (hasReminder) ...[
                  const SizedBox(height: 12),
                  const Text('Godzina przypomnienia',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF718096),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: selectedTime ?? TimeOfDay.now(),
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4F8),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: const Color(0xFFCBD5E0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time,
                              color: Color(0xFF2B6CB0), size: 20),
                          const SizedBox(width: 10),
                          Text(
                            selectedTime != null
                                ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                                : 'Wybierz godzinę...',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: selectedTime != null
                                  ? const Color(0xFF2B6CB0)
                                  : const Color(0xFFA0AEC0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Typ powiadomienia',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF718096),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setDialogState(() => isRepeating = false),
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !isRepeating
                                  ? const Color(0xFF2B6CB0)
                                  : const Color(0xFFF0F4F8),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: !isRepeating
                                    ? const Color(0xFF2B6CB0)
                                    : const Color(0xFFCBD5E0),
                              ),
                            ),
                            child: Text(
                              'Jednorazowe',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: !isRepeating
                                    ? Colors.white
                                    : const Color(0xFF4A5568),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setDialogState(() => isRepeating = true),
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isRepeating
                                  ? const Color(0xFF2B6CB0)
                                  : const Color(0xFFF0F4F8),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isRepeating
                                    ? const Color(0xFF2B6CB0)
                                    : const Color(0xFFCBD5E0),
                              ),
                            ),
                            child: Text(
                              'Powtarzające',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isRepeating
                                    ? Colors.white
                                    : const Color(0xFF4A5568),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isRepeating) ...[
                    const SizedBox(height: 12),
                    const Text('Powtarzaj co',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF718096),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [10, 15, 30].map((mins) {
                        bool selected = selectedRepeatMinutes == mins;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setDialogState(
                                () => selectedRepeatMinutes = mins),
                            child: Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF2C7A4B)
                                    : const Color(0xFFF0F4F8),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF2C7A4B)
                                      : const Color(0xFFCBD5E0),
                                ),
                              ),
                              child: Text(
                                '$mins min',
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
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anuluj'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final name = nameController.text.trim();
                final time = hasReminder && selectedTime != null
                    ? '${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}'
                    : null;
                final repeat =
                    hasReminder && isRepeating ? selectedRepeatMinutes : null;
                Navigator.pop(ctx);

                // Anuluj stare powiadomienie
                await _cancelTaskNotification(task['id']);

                // Zaktualizuj w Firebase
                await _firestoreService.updateDailyTask(
                    task['id'], name, time, repeat);

                // Zaplanuj nowe powiadomienie
                if (hasReminder && selectedTime != null) {
                  await _scheduleTaskNotification(
                      task['id'], name, time!, repeat);
                }
              },
              child: const Text('Zapisz'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, bool isDaily) {
    bool done = task['done'] as bool;
    return GestureDetector(
      onTap: () {
        if (isDaily) {
          _firestoreService.toggleDailyTask(task['id'], !done);
          if (!done && task['time'] != null) {
            _cancelTaskNotification(task['id']);
          }
        } else {
          _firestoreService.toggleExtraTask(task['id'], !done);
        }
      },
      onLongPress: () => isDaily
          ? _showTaskOptions(task)
          : _confirmDeleteTask(task['id'], false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: done ? const Color(0xFFF7F7F7) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: isDaily
                  ? const Color(0xFF2B6CB0)
                  : const Color(0xFF2C7A4B),
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
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: done ? const Color(0xFF2C7A4B) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: done
                      ? const Color(0xFF2C7A4B)
                      : const Color(0xFFCBD5E0),
                  width: 2.5,
                ),
              ),
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task['name'],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: done
                          ? const Color(0xFFA0AEC0)
                          : const Color(0xFF2D3748),
                      decoration: done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  if (task['time'] != null)
                    Text(
                      'Przypomnienie o ${task['time']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFA0AEC0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            if (task['time'] != null)
              const Icon(Icons.notifications_active,
                  size: 18, color: Color(0xFFA0AEC0)),
          ],
        ),
      ),
    );
  }

  // Menu opcji dla zadania codziennego
  void _showTaskOptions(Map<String, dynamic> task) {
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 8),
              child: Text(
                task['name'],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D3748),
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: Color(0xFF2B6CB0)),
              title: const Text('Edytuj zadanie'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditDailyTaskDialog(task);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Usuń zadanie',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteTask(task['id'], true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTask(String id, bool isDaily) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usuń zadanie'),
        content: const Text('Czy na pewno chcesz usunąć to zadanie?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              if (isDaily) {
                _cancelTaskNotification(id);
                _firestoreService.deleteDailyTask(id);
              } else {
                _firestoreService.deleteExtraTask(id);
              }
            },
            child: const Text('Usuń',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _showAddTaskDialog,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBD5E0), width: 2),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: Color(0xFF718096)),
            SizedBox(width: 8),
            Text(
              'Dodaj zadanie dodatkowe',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF718096),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTaskDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nowe zadanie dodatkowe'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Nazwa zadania...'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _firestoreService.addExtraTask(controller.text, null);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Dodaj'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) => setState(() => _currentIndex = i),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: const Color(0xFF2B6CB0),
      unselectedItemColor: const Color(0xFFA0AEC0),
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.checklist), label: 'Lista'),
        BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'Budziki'),
        BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'Nagrania'),
        BottomNavigationBarItem(
            icon: Icon(Icons.settings), label: 'Ustawienia'),
      ],
    );
  }

  String _getTodayDate() {
    final now = DateTime.now();
    final days = [
      'Poniedziałek', 'Wtorek', 'Środa', 'Czwartek',
      'Piątek', 'Sobota', 'Niedziela'
    ];
    final months = [
      'stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca',
      'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia'
    ];
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }
}