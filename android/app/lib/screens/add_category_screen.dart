import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/category_form.dart';

/// Add a category: emoji + name + kind. Writes to drift + outbox.
class AddCategoryScreen extends StatelessWidget {
  const AddCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add category')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CategoryForm(onSaved: (_, _) => context.pop()),
        ],
      ),
    );
  }
}
