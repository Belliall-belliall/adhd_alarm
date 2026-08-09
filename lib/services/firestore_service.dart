import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _pairingCode = 'DEFAULT_CODE';

  CollectionReference<Map<String, dynamic>> get _dailyTasks =>
      _db.collection('pairs').doc(_pairingCode).collection('daily_tasks');

  CollectionReference<Map<String, dynamic>> get _extraTasks =>
      _db.collection('pairs').doc(_pairingCode).collection('extra_tasks');

  CollectionReference<Map<String, dynamic>> get _alarms =>
      _db.collection('pairs').doc(_pairingCode).collection('alarms');

  // ─── ZADANIA CODZIENNE ───────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> getDailyTasks() {
    return _dailyTasks.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'done': data['done'] ?? false,
          'time': data['time'],
          'repeatMinutes': data['repeatMinutes'],
        };
      }).toList();
    });
  }

  // Stara metoda – zachowana dla kompatybilności
  Future<void> addDailyTask(String name, String? time) async {
    if (name.trim().isEmpty) return;
    try {
      await _dailyTasks.add({
        'name': name.trim(),
        'done': false,
        'time': time,
        'repeatMinutes': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Błąd dodawania zadania codziennego: $e');
    }
  }

  // Nowa metoda – zwraca ID zadania, obsługuje powtarzanie
  Future<String> addDailyTaskWithReminder(
      String name, String? time, int? repeatMinutes) async {
    if (name.trim().isEmpty) return '';
    try {
      final doc = await _dailyTasks.add({
        'name': name.trim(),
        'done': false,
        'time': time,
        'repeatMinutes': repeatMinutes,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      debugPrint('Błąd dodawania zadania codziennego: $e');
      return '';
    }
  }

  Future<void> toggleDailyTask(String id, bool done) async {
    try {
      await _dailyTasks.doc(id).update({
        'done': done,
        'doneAt': done ? FieldValue.serverTimestamp() : null,
      });
    } catch (e) {
      debugPrint('Błąd aktualizacji zadania codziennego: $e');
    }
  }

  Future<void> deleteDailyTask(String id) async {
    try {
      await _dailyTasks.doc(id).delete();
    } catch (e) {
      debugPrint('Błąd usuwania zadania codziennego: $e');
    }
  }

  Future<void> resetDailyTasks() async {
    try {
      final snapshot = await _dailyTasks.get();
      final batch = _db.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'done': false, 'doneAt': null});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Błąd resetowania zadań codziennych: $e');
    }
  }

  Future<void> initializeDefaultTasks() async {
    try {
      final snapshot = await _dailyTasks.get();
      if (snapshot.docs.isEmpty) {
        await addDailyTask('Weź leki poranne', '08:00');
        await addDailyTask('Śniadanie', null);
        await addDailyTask('Weź leki południowe', '12:00');
        await addDailyTask('Spacer lub ćwiczenia', null);
      }
    } catch (e) {
      debugPrint('Błąd inicjalizacji zadań domyślnych: $e');
    }
  }

  Future<void> checkAndResetDailyTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastReset = prefs.getString('last_reset');
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (lastReset != today) {
        await resetDailyTasks();
        await prefs.setString('last_reset', today);
      }
    } catch (e) {
      debugPrint('Błąd sprawdzania resetu: $e');
    }
  }

  // ─── ZADANIA DODATKOWE ───────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> getExtraTasks() {
    return _extraTasks.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'done': data['done'] ?? false,
          'time': data['time'],
        };
      }).toList();
    });
  }

  Future<void> addExtraTask(String name, String? time) async {
    if (name.trim().isEmpty) return;
    try {
      await _extraTasks.add({
        'name': name.trim(),
        'done': false,
        'time': time,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Błąd dodawania zadania dodatkowego: $e');
    }
  }

  Future<void> toggleExtraTask(String id, bool done) async {
    try {
      await _extraTasks.doc(id).update({
        'done': done,
        'doneAt': done ? FieldValue.serverTimestamp() : null,
      });
    } catch (e) {
      debugPrint('Błąd aktualizacji zadania dodatkowego: $e');
    }
  }

  Future<void> deleteExtraTask(String id) async {
    try {
      await _extraTasks.doc(id).delete();
    } catch (e) {
      debugPrint('Błąd usuwania zadania dodatkowego: $e');
    }
  }
Future<void> updateDailyTask(
      String id, String name, String? time, int? repeatMinutes) async {
    if (name.trim().isEmpty) return;
    try {
      await _dailyTasks.doc(id).update({
        'name': name.trim(),
        'time': time,
        'repeatMinutes': repeatMinutes,
      });
    } catch (e) {
      debugPrint('Błąd aktualizacji zadania codziennego: $e');
    }
  }
  // ─── BUDZIKI ─────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> getAlarms() {
    return _alarms.orderBy('time').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'time': data['time'] ?? '00:00',
          'label': data['label'] ?? 'Budzik',
          'checkTime': data['checkTime'] ?? '30 min',
          'active': data['active'] ?? true,
        };
      }).toList();
    });
  }

  Future<String> addAlarm(String time, String label, String checkTime) async {
    try {
      final doc = await _alarms.add({
        'time': time,
        'label': label.trim().isEmpty ? 'Budzik' : label.trim(),
        'checkTime': checkTime,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      debugPrint('Błąd dodawania budzika: $e');
      return '';
    }
  }

  Future<void> toggleAlarm(String id, bool active) async {
    try {
      await _alarms.doc(id).update({'active': active});
    } catch (e) {
      debugPrint('Błąd aktualizacji budzika: $e');
    }
  }

  Future<void> deleteAlarm(String id) async {
    try {
      await _alarms.doc(id).delete();
    } catch (e) {
      debugPrint('Błąd usuwania budzika: $e');
    }
  }
  Future<void> updateAlarm(
      String id, String time, String label, String checkTime) async {
    try {
      await _alarms.doc(id).update({
        'time': time,
        'label': label.trim().isEmpty ? 'Budzik' : label.trim(),
        'checkTime': checkTime,
      });
    } catch (e) {
      debugPrint('Błąd aktualizacji budzika: $e');
    }
  }
  
}
