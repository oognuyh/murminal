import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/services/engine_registry.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8);
const _textMuted = Color(0xFF475569);
const _surfaceBorder = Color(0xFF334155);

/// Names of bundled profiles that ship with the app.
///
/// User profiles are any profiles registered at runtime whose name
/// does not appear in this set. Bundled profiles are read-only.
const _bundledProfileNames = <String>{
  'claude',
  'chatgpt',
  'default',
  'shell',
};

/// Screen for listing, viewing, creating, and editing engine profiles.
///
/// Bundled profiles are displayed but cannot be edited. User-created
/// profiles support full CRUD operations. New profiles can be created
/// from scratch or by cloning an existing profile as a template.
class EngineProfileScreen extends ConsumerStatefulWidget {
  const EngineProfileScreen({super.key});

  @override
  ConsumerState<EngineProfileScreen> createState() =>
      _EngineProfileScreenState();
}

class _EngineProfileScreenState extends ConsumerState<EngineProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(engineRegistryProvider);
    final profiles = registry.profiles;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: const Text(
          'Engine Profiles',
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 18,
            letterSpacing: 1,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: _accent),
            tooltip: 'Create profile',
            onPressed: () => _openEditor(context, registry, null),
          ),
        ],
      ),
      body: profiles.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: profiles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final profile = profiles[index];
                final isBundled = _bundledProfileNames.contains(profile.name);
                return _ProfileListTile(
                  profile: profile,
                  isBundled: isBundled,
                  onTap: () => _showProfileDetail(context, registry, profile),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.settings_suggest_outlined, size: 48, color: _textMuted),
          SizedBox(height: 16),
          Text(
            'No engine profiles loaded',
            style: TextStyle(color: _textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  void _showProfileDetail(
    BuildContext context,
    EngineRegistry registry,
    EngineProfile profile,
  ) {
    final isBundled = _bundledProfileNames.contains(profile.name);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileDetailScreen(
          profile: profile,
          isBundled: isBundled,
          onEdit: isBundled
              ? null
              : () {
                  Navigator.of(context).pop();
                  _openEditor(context, registry, profile);
                },
          onDelete: isBundled
              ? null
              : () {
                  registry.unregister(profile.name);
                  Navigator.of(context).pop();
                  setState(() {});
                },
          onClone: () {
            Navigator.of(context).pop();
            _openEditor(context, registry, profile, isClone: true);
          },
          onReset: isBundled
              ? null
              : () {
                  // Reset removes the user profile so the bundled one
                  // (if any) takes precedence on next load.
                  registry.unregister(profile.name);
                  Navigator.of(context).pop();
                  setState(() {});
                },
        ),
      ),
    );
  }

  void _openEditor(
    BuildContext context,
    EngineRegistry registry,
    EngineProfile? profile, {
    bool isClone = false,
  }) async {
    final result = await Navigator.of(context).push<EngineProfile>(
      MaterialPageRoute<EngineProfile>(
        builder: (_) => _ProfileEditorScreen(
          profile: profile,
          isClone: isClone,
        ),
      ),
    );

    if (result != null) {
      registry.register(result);
      setState(() {});
    }
  }
}

/// List tile showing profile name, type, and bundled/user badge.
class _ProfileListTile extends StatelessWidget {
  final EngineProfile profile;
  final bool isBundled;
  final VoidCallback onTap;

  const _ProfileListTile({
    required this.profile,
    required this.isBundled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accent.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  isBundled ? Icons.inventory_2_outlined : Icons.tune,
                  color: _accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.type} / ${profile.inputMode}',
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isBundled
                      ? _textMuted.withAlpha(30)
                      : _accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isBundled ? 'BUNDLED' : 'USER',
                  style: TextStyle(
                    color: isBundled ? _textMuted : _accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: _textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail screen showing all profile fields in read-only mode.
class _ProfileDetailScreen extends StatelessWidget {
  final EngineProfile profile;
  final bool isBundled;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onClone;
  final VoidCallback? onReset;

  const _ProfileDetailScreen({
    required this.profile,
    required this.isBundled,
    this.onEdit,
    this.onDelete,
    required this.onClone,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: Text(
          profile.displayName,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 18,
            letterSpacing: 1,
          ),
        ),
        actions: [
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit, color: _accent),
              tooltip: 'Edit profile',
              onPressed: onEdit,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: _textSecondary),
            color: _surface,
            onSelected: (value) {
              switch (value) {
                case 'clone':
                  onClone();
                case 'reset':
                  onReset?.call();
                case 'delete':
                  _confirmDelete(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'clone',
                child: Text('Create from template',
                    style: TextStyle(color: _textPrimary)),
              ),
              if (onReset != null)
                const PopupMenuItem(
                  value: 'reset',
                  child: Text('Reset to default',
                      style: TextStyle(color: _textPrimary)),
                ),
              if (onDelete != null)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete',
                      style: TextStyle(color: Color(0xFFEF4444))),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _sectionHeader('General'),
          _fieldRow('Name', profile.name),
          _fieldRow('Display Name', profile.displayName),
          _fieldRow('Type', profile.type),
          _fieldRow('Input Mode', profile.inputMode),
          const SizedBox(height: 20),
          _sectionHeader('Launch'),
          _fieldRow('Command', profile.launch.command ?? '(none)'),
          if (profile.launch.flags.isNotEmpty)
            _fieldRow('Flags', profile.launch.flags.join(' ')),
          if (profile.launch.env.isNotEmpty)
            ...profile.launch.env.entries
                .map((e) => _fieldRow('ENV ${e.key}', e.value)),
          const SizedBox(height: 20),
          if (profile.patterns.isNotEmpty) ...[
            _sectionHeader('Patterns'),
            ...profile.patterns.entries.map(
              (e) => _codeFieldRow(e.key, e.value ?? '(null)'),
            ),
            const SizedBox(height: 20),
          ],
          if (profile.states.isNotEmpty) ...[
            _sectionHeader('States'),
            ...profile.states.entries.map(
              (e) => _stateCard(e.key, e.value),
            ),
            const SizedBox(height: 20),
          ],
          if (profile.reportTemplates.isNotEmpty) ...[
            _sectionHeader('Report Templates'),
            ...profile.reportTemplates.entries.map(
              (e) => _codeFieldRow(e.key, e.value),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: _textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }

  Widget _fieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: _textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeFieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: _textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _surfaceBorder),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: _accent,
                fontSize: 12,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateCard(String stateName, StateConfig config) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stateName,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Indicator: ${config.indicator}',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            if (config.priority != null)
              Text(
                'Priority: ${config.priority}',
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            Text(
              'Report: ${config.report ? "yes" : "no"}',
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Delete Profile',
            style: TextStyle(color: _textPrimary)),
        content: Text(
          'Delete "${profile.displayName}"? This cannot be undone.',
          style: const TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: _textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete?.call();
            },
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }
}

/// Editor screen for creating or modifying an engine profile.
class _ProfileEditorScreen extends StatefulWidget {
  final EngineProfile? profile;
  final bool isClone;

  const _ProfileEditorScreen({this.profile, this.isClone = false});

  @override
  State<_ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<_ProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _typeController;
  late final TextEditingController _inputModeController;
  late final TextEditingController _commandController;
  late final TextEditingController _flagsController;

  late final List<_PatternEntry> _patterns;
  late final List<_StateEntry> _states;
  late final List<_TemplateEntry> _reportTemplates;

  bool get _isEditing => widget.profile != null && !widget.isClone;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;

    _nameController = TextEditingController(
      text: widget.isClone ? '' : (p?.name ?? ''),
    );
    _displayNameController = TextEditingController(
      text: widget.isClone ? '' : (p?.displayName ?? ''),
    );
    _typeController = TextEditingController(text: p?.type ?? 'cli');
    _inputModeController = TextEditingController(text: p?.inputMode ?? 'line');
    _commandController = TextEditingController(text: p?.launch.command ?? '');
    _flagsController = TextEditingController(
      text: p?.launch.flags.join(' ') ?? '',
    );

    _patterns = p?.patterns.entries
            .map((e) => _PatternEntry(
                  keyController: TextEditingController(text: e.key),
                  valueController: TextEditingController(text: e.value ?? ''),
                ))
            .toList() ??
        [];

    _states = p?.states.entries
            .map((e) => _StateEntry(
                  nameController: TextEditingController(text: e.key),
                  indicatorController:
                      TextEditingController(text: e.value.indicator),
                  priorityController:
                      TextEditingController(text: e.value.priority ?? ''),
                  report: e.value.report,
                ))
            .toList() ??
        [];

    _reportTemplates = p?.reportTemplates.entries
            .map((e) => _TemplateEntry(
                  keyController: TextEditingController(text: e.key),
                  valueController: TextEditingController(text: e.value),
                ))
            .toList() ??
        [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _typeController.dispose();
    _inputModeController.dispose();
    _commandController.dispose();
    _flagsController.dispose();
    for (final p in _patterns) {
      p.keyController.dispose();
      p.valueController.dispose();
    }
    for (final s in _states) {
      s.nameController.dispose();
      s.indicatorController.dispose();
      s.priorityController.dispose();
    }
    for (final t in _reportTemplates) {
      t.keyController.dispose();
      t.valueController.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final patterns = <String, String?>{};
    for (final p in _patterns) {
      final key = p.keyController.text.trim();
      if (key.isNotEmpty) {
        final value = p.valueController.text;
        patterns[key] = value.isEmpty ? null : value;
      }
    }

    final states = <String, StateConfig>{};
    for (final s in _states) {
      final name = s.nameController.text.trim();
      if (name.isNotEmpty) {
        states[name] = StateConfig(
          indicator: s.indicatorController.text.trim(),
          report: s.report,
          priority: s.priorityController.text.trim().isEmpty
              ? null
              : s.priorityController.text.trim(),
        );
      }
    }

    final templates = <String, String>{};
    for (final t in _reportTemplates) {
      final key = t.keyController.text.trim();
      if (key.isNotEmpty) {
        templates[key] = t.valueController.text;
      }
    }

    final flags = _flagsController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((f) => f.isNotEmpty)
        .toList();

    final profile = EngineProfile(
      name: _nameController.text.trim(),
      displayName: _displayNameController.text.trim(),
      type: _typeController.text.trim(),
      inputMode: _inputModeController.text.trim(),
      launch: LaunchConfig(
        command:
            _commandController.text.trim().isEmpty
                ? null
                : _commandController.text.trim(),
        flags: flags,
      ),
      patterns: patterns,
      states: states,
      reportTemplates: templates,
    );

    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing
        ? 'Edit Profile'
        : widget.isClone
            ? 'New from Template'
            : 'New Profile';

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 18,
            letterSpacing: 1,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(
                color: _accent,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              _sectionLabel('GENERAL'),
              _buildField(
                controller: _nameController,
                label: 'Name (unique key)',
                hint: 'my-engine',
                validator: _requiredValidator('Name is required'),
                readOnly: _isEditing,
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _displayNameController,
                label: 'Display Name',
                hint: 'My Engine',
                validator: _requiredValidator('Display name is required'),
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _typeController,
                label: 'Type',
                hint: 'cli',
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _inputModeController,
                label: 'Input Mode',
                hint: 'line',
              ),
              const SizedBox(height: 24),
              _sectionLabel('LAUNCH'),
              _buildField(
                controller: _commandController,
                label: 'Command',
                hint: '/usr/bin/my-engine',
                isCode: true,
              ),
              const SizedBox(height: 14),
              _buildField(
                controller: _flagsController,
                label: 'Flags (space-separated)',
                hint: '--verbose --no-color',
                isCode: true,
              ),
              const SizedBox(height: 24),
              _buildDynamicSection(
                label: 'PATTERNS',
                entries: _patterns,
                onAdd: () {
                  setState(() {
                    _patterns.add(_PatternEntry(
                      keyController: TextEditingController(),
                      valueController: TextEditingController(),
                    ));
                  });
                },
                itemBuilder: (index) {
                  final entry = _patterns[index];
                  return _buildKeyValueRow(
                    keyController: entry.keyController,
                    valueController: entry.valueController,
                    keyHint: 'pattern_name',
                    valueHint: r'regex pattern',
                    isCode: true,
                    onRemove: () {
                      setState(() {
                        entry.keyController.dispose();
                        entry.valueController.dispose();
                        _patterns.removeAt(index);
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              _buildStatesSection(),
              const SizedBox(height: 24),
              _buildDynamicSection(
                label: 'REPORT TEMPLATES',
                entries: _reportTemplates,
                onAdd: () {
                  setState(() {
                    _reportTemplates.add(_TemplateEntry(
                      keyController: TextEditingController(),
                      valueController: TextEditingController(),
                    ));
                  });
                },
                itemBuilder: (index) {
                  final entry = _reportTemplates[index];
                  return _buildKeyValueRow(
                    keyController: entry.keyController,
                    valueController: entry.valueController,
                    keyHint: 'template_name',
                    valueHint: 'Template text with {placeholders}',
                    isCode: true,
                    onRemove: () {
                      setState(() {
                        entry.keyController.dispose();
                        entry.valueController.dispose();
                        _reportTemplates.removeAt(index);
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: const TextStyle(
          color: _textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    bool readOnly = false,
    bool isCode = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          readOnly: readOnly,
          style: TextStyle(
            color: readOnly ? _textMuted : _textPrimary,
            fontFamily: isCode ? 'JetBrains Mono' : null,
            fontSize: 13,
          ),
          cursorColor: _accent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: _textMuted,
              fontFamily: isCode ? 'JetBrains Mono' : null,
              fontSize: 13,
            ),
            filled: true,
            fillColor: readOnly ? _surface.withAlpha(120) : _surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _surfaceBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _surfaceBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _accent, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
            ),
            errorStyle: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicSection<T>({
    required String label,
    required List<T> entries,
    required VoidCallback onAdd,
    required Widget Function(int index) itemBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel(label),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  color: _accent, size: 20),
              onPressed: onAdd,
              tooltip: 'Add entry',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        ...List.generate(entries.length, itemBuilder),
      ],
    );
  }

  Widget _buildKeyValueRow({
    required TextEditingController keyController,
    required TextEditingController valueController,
    required String keyHint,
    required String valueHint,
    bool isCode = false,
    required VoidCallback onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: keyController,
              style: TextStyle(
                color: _textPrimary,
                fontFamily: isCode ? 'JetBrains Mono' : null,
                fontSize: 12,
              ),
              cursorColor: _accent,
              decoration: InputDecoration(
                hintText: keyHint,
                hintStyle: TextStyle(
                  color: _textMuted,
                  fontFamily: isCode ? 'JetBrains Mono' : null,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: _surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _surfaceBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _accent, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: valueController,
              style: TextStyle(
                color: _accent,
                fontFamily: isCode ? 'JetBrains Mono' : null,
                fontSize: 12,
              ),
              cursorColor: _accent,
              decoration: InputDecoration(
                hintText: valueHint,
                hintStyle: TextStyle(
                  color: _textMuted,
                  fontFamily: isCode ? 'JetBrains Mono' : null,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: _surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _surfaceBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _accent, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                color: Color(0xFFEF4444), size: 18),
            onPressed: onRemove,
            padding: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('STATES'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  color: _accent, size: 20),
              onPressed: () {
                setState(() {
                  _states.add(_StateEntry(
                    nameController: TextEditingController(),
                    indicatorController: TextEditingController(),
                    priorityController: TextEditingController(),
                    report: false,
                  ));
                });
              },
              tooltip: 'Add state',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        ...List.generate(_states.length, (index) {
          final entry = _states[index];
          return _buildStateRow(entry, index);
        }),
      ],
    );
  }

  Widget _buildStateRow(_StateEntry entry, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _surfaceBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: entry.nameController,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: _accent,
                  decoration: const InputDecoration(
                    hintText: 'State name',
                    hintStyle: TextStyle(color: _textMuted, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Color(0xFFEF4444), size: 18),
                onPressed: () {
                  setState(() {
                    entry.nameController.dispose();
                    entry.indicatorController.dispose();
                    entry.priorityController.dispose();
                    _states.removeAt(index);
                  });
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: entry.indicatorController,
            style: const TextStyle(
              color: _accent,
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
            ),
            cursorColor: _accent,
            decoration: const InputDecoration(
              hintText: 'Indicator text',
              hintStyle: TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontFamily: 'JetBrains Mono',
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: entry.priorityController,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
            ),
            cursorColor: _accent,
            decoration: const InputDecoration(
              hintText: 'Priority (optional)',
              hintStyle: TextStyle(
                color: _textMuted,
                fontSize: 12,
                fontFamily: 'JetBrains Mono',
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                'Report',
                style: TextStyle(color: _textSecondary, fontSize: 12),
              ),
              const Spacer(),
              SizedBox(
                height: 24,
                child: Switch.adaptive(
                  value: entry.report,
                  activeColor: _accent,
                  onChanged: (v) => setState(() => entry.report = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  FormFieldValidator<String> _requiredValidator(String message) {
    return (value) {
      if (value == null || value.trim().isEmpty) return message;
      return null;
    };
  }
}

/// Mutable holder for a pattern key-value pair in the editor.
class _PatternEntry {
  final TextEditingController keyController;
  final TextEditingController valueController;

  _PatternEntry({
    required this.keyController,
    required this.valueController,
  });
}

/// Mutable holder for a state config entry in the editor.
class _StateEntry {
  final TextEditingController nameController;
  final TextEditingController indicatorController;
  final TextEditingController priorityController;
  bool report;

  _StateEntry({
    required this.nameController,
    required this.indicatorController,
    required this.priorityController,
    required this.report,
  });
}

/// Mutable holder for a report template entry in the editor.
class _TemplateEntry {
  final TextEditingController keyController;
  final TextEditingController valueController;

  _TemplateEntry({
    required this.keyController,
    required this.valueController,
  });
}
