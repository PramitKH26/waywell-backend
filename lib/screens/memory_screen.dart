import 'package:flutter/material.dart';

import 'memory_wall_screen.dart';

/// "Me" tab — currently just routes straight into the Memory Wall.
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MemoryWallScreen();
  }
}
