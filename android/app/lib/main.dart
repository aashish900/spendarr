import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/seed_categories.dart';
import 'router.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(child: SpendarrApp()));
}

class SpendarrApp extends ConsumerWidget {
  const SpendarrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fire-and-forget: default categories appear reactively once seeded, no
    // need to gate the first frame on this.
    ref.watch(seedDefaultCategoriesProvider);

    return MaterialApp.router(
      title: 'spendarr',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      routerConfig: appRouter,
    );
  }
}
