// Copyright 2024 Lumina Reader Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';

class EpubReaderScreen extends StatelessWidget {
  const EpubReaderScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EpubReaderScreen')),
      body: const Center(child: Text('Coming soon')),
    );
  }
}
