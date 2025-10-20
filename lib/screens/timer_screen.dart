import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/colors.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  int _totalSeconds = 25 * 60; // 25 minutes default
  int _remainingSeconds = 25 * 60;
  bool _isRunning = false;
  bool _isPaused = false;
  Timer? _timer;
  String _currentMode = 'Focus';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _isRunning = true;
      _isPaused = false;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _timer?.cancel();
          _isRunning = false;
          // Timer completed
        }
      });
    });
  }

  void _pauseTimer() {
    setState(() {
      _isPaused = true;
      _isRunning = false;
    });
    _timer?.cancel();
  }

  void _resetTimer() {
    setState(() {
      _timer?.cancel();
      _isRunning = false;
      _isPaused = false;
      _remainingSeconds = _totalSeconds;
    });
  }

  void _setMode(String mode, int minutes) {
    setState(() {
      _currentMode = mode;
      _totalSeconds = minutes * 60;
      _remainingSeconds = minutes * 60;
      _isRunning = false;
      _isPaused = false;
    });
    _timer?.cancel();
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  double get _progress => 1 - (_remainingSeconds / _totalSeconds);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Focus Timer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),

          // Mode Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildModeButton(
                    'Focus',
                    25,
                    AppColors.pink,
                    _currentMode == 'Focus',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildModeButton(
                    'Short Break',
                    5,
                    AppColors.cyan,
                    _currentMode == 'Short Break',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildModeButton(
                    'Long Break',
                    15,
                    AppColors.yellow,
                    _currentMode == 'Long Break',
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Timer Circle
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Progress Circle
                SizedBox(
                  width: 280,
                  height: 280,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 12,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _currentMode == 'Focus'
                          ? AppColors.pink
                          : _currentMode == 'Short Break'
                              ? AppColors.cyan
                              : AppColors.yellow,
                    ),
                  ),
                ),

                // Timer Display
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(_remainingSeconds),
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentMode,
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(),

          // Control Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Reset Button
                if (_isPaused || _remainingSeconds != _totalSeconds)
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.refresh),
                      color: AppColors.textPrimary,
                      onPressed: _resetTimer,
                    ),
                  ),
                if (_isPaused || _remainingSeconds != _totalSeconds)
                  const SizedBox(width: 24),

                // Play/Pause Button
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _currentMode == 'Focus'
                        ? AppColors.pink
                        : _currentMode == 'Short Break'
                            ? AppColors.cyan
                            : AppColors.yellow,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_currentMode == 'Focus'
                                ? AppColors.pink
                                : _currentMode == 'Short Break'
                                    ? AppColors.cyan
                                    : AppColors.yellow)
                            .withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isRunning ? Icons.pause : Icons.play_arrow,
                      size: 40,
                    ),
                    color: Colors.white,
                    onPressed: _isRunning ? _pauseTimer : _startTimer,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // Session Info
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Sessions', '4', Icons.check_circle),
                Container(
                  width: 1,
                  height: 40,
                  color: AppColors.border,
                ),
                _buildStatItem('Focus Time', '1h 40m', Icons.timer),
                Container(
                  width: 1,
                  height: 40,
                  color: AppColors.border,
                ),
                _buildStatItem('Break Time', '20m', Icons.coffee),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildModeButton(String label, int minutes, Color color, bool isSelected) {
    return Material(
      color: isSelected ? color : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _setMode(label, minutes),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AppColors.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.pink),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
