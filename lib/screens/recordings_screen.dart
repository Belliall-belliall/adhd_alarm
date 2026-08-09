import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  // Subskrypcja tworzona raz w initState i anulowana w dispose
  late final StreamSubscription<void> _playerCompleteSubscription;

  bool _isRecording = false;
  bool _isPlaying = false;
  List<Map<String, dynamic>> _recordings = [];
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    _loadRecordings();

    // Listener tworzony tylko raz
    _playerCompleteSubscription = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _playingPath = null;
      });
    });
  }

  @override
  void dispose() {
    // Anulowanie subskrypcji i zwalnianie zasobów
    _playerCompleteSubscription.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<String> get _recordingsDir async {
    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${dir.path}/recordings');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    return recordingsDir.path;
  }

  Future<void> _loadRecordings() async {
    try {
      final dir = await _recordingsDir;
      final directory = Directory(dir);
      if (await directory.exists()) {
        final files = directory
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.m4a'))
            .toList();
        files.sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

        // Sprawdzamy mounted przed setState
        if (!mounted) return;
        setState(() {
          _recordings = files.map((f) {
            final name = f.path.split('/').last.split('\\').last;
            return {
              'path': f.path,
              'name': name.replaceAll('.m4a', ''),
              'date': f.lastModifiedSync(),
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Błąd ładowania nagrań: $e');
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak uprawnień do mikrofonu!')),
      );
      return;
    }

    try {
      final dir = await _recordingsDir;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '$dir/nagranie_$timestamp.m4a';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      if (!mounted) return;
      setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('Błąd rozpoczęcia nagrywania: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się rozpocząć nagrywania.')),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recorder.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      await _loadRecordings();
    } catch (e) {
      debugPrint('Błąd zatrzymania nagrywania: $e');
    }
  }

  Future<void> _playRecording(String path) async {
    try {
      if (_isPlaying && _playingPath == path) {
        await _player.stop();
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _playingPath = null;
        });
        return;
      }

      await _player.stop();
      await _player.play(DeviceFileSource(path));
      if (!mounted) return;
      setState(() {
        _isPlaying = true;
        _playingPath = path;
      });
    } catch (e) {
      debugPrint('Błąd odtwarzania nagrania: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się odtworzyć nagrania.')),
      );
    }
  }

  Future<void> _deleteRecording(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      await _loadRecordings();
    } catch (e) {
      debugPrint('Błąd usuwania nagrania: $e');
    }
  }

  Future<void> _renameRecording(String path, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zmień nazwę'),
        content: TextField(
          controller: controller,
          maxLength: 50,
          decoration:
              const InputDecoration(hintText: 'Nazwa nagrania...'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    try {
      final dir = await _recordingsDir;
      final newPath = '$dir/$newName.m4a';

      // Sprawdzamy czy plik o tej nazwie już istnieje
      if (await File(newPath).exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nagranie o tej nazwie już istnieje.')),
        );
        return;
      }

      await File(path).rename(newPath);
      await _loadRecordings();
    } catch (e) {
      debugPrint('Błąd zmiany nazwy nagrania: $e');
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
            _buildRecordButton(),
            Expanded(
              child: _recordings.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _recordings.length,
                      itemBuilder: (context, index) =>
                          _buildRecordingCard(_recordings[index]),
                    ),
            ),
          ],
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
            'Nagrania głosowe',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Nagraj notatkę głosową do budzika',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordButton() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            _isRecording ? 'Nagrywanie...' : 'Naciśnij aby nagrać',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color:
                  _isRecording ? Colors.red : const Color(0xFF4A5568),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _isRecording ? _stopRecording : _startRecording,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _isRecording
                    ? Colors.red
                    : const Color(0xFF2B6CB0),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording
                            ? Colors.red
                            : const Color(0xFF2B6CB0))
                        .withOpacity(0.4),
                    blurRadius: 16,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 36,
              ),
            ),
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
          Icon(Icons.mic_none, size: 64, color: Color(0xFFA0AEC0)),
          SizedBox(height: 16),
          Text(
            'Brak nagrań',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A5568),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Naciśnij przycisk mikrofonu\naby nagrać pierwszą notatkę',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 14, color: Color(0xFF718096)),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingCard(Map<String, dynamic> recording) {
    bool isThisPlaying =
        _isPlaying && _playingPath == recording['path'];
    final date = recording['date'] as DateTime;
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(
            color: isThisPlaying
                ? const Color(0xFF2C7A4B)
                : const Color(0xFF2B6CB0),
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
          GestureDetector(
            onTap: () => _playRecording(recording['path']),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isThisPlaying
                    ? const Color(0xFF2C7A4B)
                    : const Color(0xFF2B6CB0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isThisPlaying ? Icons.stop : Icons.play_arrow,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recording['name'],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D3748),
                  ),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFA0AEC0),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: Color(0xFF718096), size: 20),
            onPressed: () => _renameRecording(
                recording['path'], recording['name']),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.red, size: 20),
            onPressed: () => _confirmDelete(recording['path']),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usuń nagranie'),
        content:
            const Text('Czy na pewno chcesz usunąć to nagranie?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteRecording(path);
            },
            child: const Text('Usuń',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
