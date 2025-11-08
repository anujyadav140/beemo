import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Reusable Beemo logo widget
/// Displays the custom Beemo logo SVG instead of the robot emoji
class BeemoLogo extends StatelessWidget {
  final double size;
  final BoxFit fit;

  const BeemoLogo({
    super.key,
    this.size = 38,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/beemo_logo.svg',
      width: size,
      height: size,
      fit: fit,
      placeholderBuilder: (context) {
        // Fallback to emoji if SVG not found or while loading
        return Text('🤖', style: TextStyle(fontSize: size));
      },
    );
  }
}
