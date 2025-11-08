import 'package:flutter/material.dart';
import 'dart:math' as math;

class IsometricRoom extends StatelessWidget {
  final String roomType;
  final Color floorColor;
  final Color wallColor;
  final double width;
  final double height;
  final List<Widget> furniture;

  const IsometricRoom({
    super.key,
    required this.roomType,
    required this.floorColor,
    required this.wallColor,
    required this.width,
    required this.height,
    this.furniture = const [],
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: IsometricRoomPainter(
        floorColor: floorColor,
        wallColor: wallColor,
      ),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            // Room label
            Positioned(
              top: height * 0.1,
              left: width * 0.3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  roomType,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            // Furniture items
            ...furniture,
          ],
        ),
      ),
    );
  }
}

class IsometricRoomPainter extends CustomPainter {
  final Color floorColor;
  final Color wallColor;

  IsometricRoomPainter({
    required this.floorColor,
    required this.wallColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 3;

    // Define isometric points
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Isometric angles (30 degrees)
    final angle = math.pi / 6; // 30 degrees
    final roomWidth = size.width * 0.6;
    final roomDepth = size.width * 0.6;
    final roomHeight = size.height * 0.4;

    // Floor vertices (diamond shape)
    final floorPath = Path();
    floorPath.moveTo(centerX, centerY + roomHeight * 0.3); // Front
    floorPath.lineTo(centerX + roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3); // Right
    floorPath.lineTo(centerX, centerY - roomDepth / 2 + roomHeight * 0.3); // Back
    floorPath.lineTo(centerX - roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3); // Left
    floorPath.close();

    // Draw floor with gradient
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        floorColor.withOpacity(0.8),
        floorColor,
      ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(floorPath, paint);

    // Draw floor border
    paint.shader = null;
    paint.color = Colors.black;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.5;
    canvas.drawPath(floorPath, paint);

    // Left wall
    paint.style = PaintingStyle.fill;
    final leftWallPath = Path();
    leftWallPath.moveTo(centerX - roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3); // Bottom left
    leftWallPath.lineTo(centerX, centerY - roomDepth / 2 + roomHeight * 0.3); // Bottom back
    leftWallPath.lineTo(centerX, centerY - roomDepth / 2 - roomHeight * 0.5); // Top back
    leftWallPath.lineTo(centerX - roomWidth / 2, centerY - roomDepth / 4 - roomHeight * 0.5); // Top left
    leftWallPath.close();

    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        wallColor.withOpacity(0.6),
        wallColor.withOpacity(0.8),
      ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(leftWallPath, paint);

    // Left wall border
    paint.shader = null;
    paint.color = Colors.black;
    paint.style = PaintingStyle.stroke;
    canvas.drawPath(leftWallPath, paint);

    // Right wall
    paint.style = PaintingStyle.fill;
    final rightWallPath = Path();
    rightWallPath.moveTo(centerX, centerY - roomDepth / 2 + roomHeight * 0.3); // Bottom back
    rightWallPath.lineTo(centerX + roomWidth / 2, centerY - roomDepth / 4 + roomHeight * 0.3); // Bottom right
    rightWallPath.lineTo(centerX + roomWidth / 2, centerY - roomDepth / 4 - roomHeight * 0.5); // Top right
    rightWallPath.lineTo(centerX, centerY - roomDepth / 2 - roomHeight * 0.5); // Top back
    rightWallPath.close();

    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        wallColor.withOpacity(0.7),
        wallColor,
      ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(rightWallPath, paint);

    // Right wall border
    paint.shader = null;
    paint.color = Colors.black;
    paint.style = PaintingStyle.stroke;
    canvas.drawPath(rightWallPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Isometric furniture widgets
class IsometricBed extends StatelessWidget {
  const IsometricBed({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 120,
      left: 80,
      child: Container(
        width: 80,
        height: 50,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFBA68C8),
              const Color(0xFF9C27B0),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.bed, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class IsometricChair extends StatelessWidget {
  const IsometricChair({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 150,
      left: 120,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF64B5F6),
              const Color(0xFF1976D2),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: const Icon(Icons.chair, color: Colors.white, size: 16),
      ),
    );
  }
}

class IsometricDesk extends StatelessWidget {
  const IsometricDesk({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 140,
      left: 100,
      child: Container(
        width: 60,
        height: 35,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFA1887F),
              const Color(0xFF6D4C41),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.computer, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class IsometricSofa extends StatelessWidget {
  const IsometricSofa({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 130,
      left: 90,
      child: Container(
        width: 70,
        height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF81C784),
              const Color(0xFF4CAF50),
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.weekend, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class IsometricBathroom extends StatelessWidget {
  const IsometricBathroom({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 140,
      left: 100,
      child: Container(
        width: 50,
        height: 35,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF90CAF9),
              const Color(0xFF2196F3),
            ],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.bathtub, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class IsometricKitchen extends StatelessWidget {
  const IsometricKitchen({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 135,
      left: 95,
      child: Container(
        width: 55,
        height: 38,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFFB74D),
              const Color(0xFFF57C00),
            ],
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: const Center(
          child: Icon(Icons.kitchen, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
