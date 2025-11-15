import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

/// A standardized coin icon widget using the coin.png asset
class CoinIcon extends StatelessWidget {
  const CoinIcon({
    super.key,
    this.size = 22,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/coin.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// A standardized coin display widget that shows points/coins with consistent styling
///
/// If [userId] and [houseId] are provided, it will stream real-time coin data from Firebase.
/// Otherwise, it will display the [points] value passed in.
class CoinDisplay extends StatelessWidget {
  const CoinDisplay({
    super.key,
    this.points,
    this.userId,
    this.houseId,
    this.fontSize = 18,
    this.coinSize = 22,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    this.backgroundColor = const Color(0xFFFFC400),
    this.fontWeight = FontWeight.bold,
    this.borderRadius = 18,
    this.showBorder = false,
  }) : assert(
          points != null || (userId != null && houseId != null),
          'Either points must be provided, or both userId and houseId must be provided',
        );

  final int? points;
  final String? userId;
  final String? houseId;
  final double fontSize;
  final double coinSize;
  final EdgeInsets padding;
  final Color backgroundColor;
  final FontWeight fontWeight;
  final double borderRadius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    // If userId and houseId are provided, use StreamBuilder for real-time data
    if (userId != null && houseId != null) {
      final firestoreService = FirestoreService();
      return StreamBuilder<int>(
        stream: firestoreService.getUserCoinsStream(
          userId: userId!,
          houseId: houseId!,
        ),
        builder: (context, snapshot) {
          final coinCount = snapshot.data ?? 0;
          return _buildCoinDisplay(coinCount);
        },
      );
    }

    // Otherwise use the static points value
    return _buildCoinDisplay(points ?? 0);
  }

  Widget _buildCoinDisplay(int coinCount) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder
            ? Border.all(color: Colors.black, width: 2.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            coinCount.toString(),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
            ),
          ),
          const SizedBox(width: 6),
          CoinIcon(size: coinSize),
        ],
      ),
    );
  }
}
