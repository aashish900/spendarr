import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/category_form.dart';
import '../widgets/gilded.dart';

/// Add or edit a category: emoji + name + kind. Writes to drift + outbox.
/// [editCategoryId], when set, loads and edits an existing category instead
/// of creating one — same card-based, gold "metallic" theme as
/// Add/Edit-transaction.
class AddCategoryScreen extends StatelessWidget {
  const AddCategoryScreen({super.key, this.editCategoryId});

  final String? editCategoryId;

  @override
  Widget build(BuildContext context) {
    final isEditing = editCategoryId != null;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          icon: Gilded(child: const Icon(Icons.arrow_back, color: Colors.white)),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text(isEditing ? 'Edit category' : 'Add category'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CategoryForm(
            editCategoryId: editCategoryId,
            onSaved: (_, _) => context.pop(),
          ),
        ],
      ),
    );
  }
}
