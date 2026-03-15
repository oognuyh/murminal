import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/engine_profile.dart';

/// Theme colors matching the app's dark slate design.
const _kBgColor = Color(0xFF0A0F1C);
const _kSurfaceColor = Color(0xFF1E293B);
const _kAccentColor = Color(0xFF22D3EE);
const _kTextPrimary = Color(0xFFFFFFFF);
const _kTextSecondary = Color(0xFF94A3B8);
const _kTextMuted = Color(0xFF475569);
const _kSurfaceBorder = Color(0xFF334155);
const _kErrorRed = Color(0xFFEF4444);

/// Screen for viewing and editing an engine profile.
///
/// When [profileName] is provided, loads the existing profile for
/// viewing (bundled) or editing (user-created). When null, creates
/// a new profile.
class EngineProfileEditorScreen extends ConsumerStatefulWidget {
  /// Name of the profile to edit, or null for new profile creation.
  final String? profileName;

  const EngineProfileEditorScreen({super.key, this.profileName});

  @override
  ConsumerState<EngineProfileEditorScreen> createState() =>
      _EngineProfileEditorScreenState();
}

class _EngineProfileEditorScreenState
    extends ConsumerState<EngineProfileEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _typeController;
  late final TextEditingController _inputModeController;
  late final TextEditingController _launchCommandController;
  late final TextEditingController _launchFlagsController;

  /// Pattern controllers keyed by pattern name.
  final Map<String, TextEditingController> _patternControllers = {};

  /// State config controllers keyed by state name.
  final Map<String, _StateConfigControllers> _stateControllers = {};

  /// Report template controllers keyed by template name.
  final Map<String, TextEditingController> _templateControllers = {};

  bool _isSaving = false;
  bool _isNew = true;
  bool _isBundled = false;
  bool _isReadOnly = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _displayNameController = TextEditingController();
    _typeController = TextEditingController();
    _inputModeController = TextEditingController();
    _launchCommandController = TextEditingController();
    _launchFlagsController = TextEditingController();

    // Defer profile loading to after the first frame so ref is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
    });
  }

  void _loadProfile() {
    final name = widget.profileName;
    if (name == null) {
      _isNew = true;
      _isBundled = false;
      _isReadOnly = false;
      return;
    }

    _isNew = false;
    final bundledNames = ref.read(bundledProfileNamesProvider);
    final userNames = ref.read(userProfileNamesProvider);
    _isBundled = bundledNames.contains(name) && !userNames.contains(name);
    _isReadOnly = _isBundled;

    final profiles = ref.read(allEngineProfilesProvider);
    final profile = profiles.where((p) => p.name == name).firstOrNull;
    if (profile == null) return;

    _nameController.text = profile.name;
    _displayNameController.text = profile.displayName;
    _typeController.text = profile.type;
    _inputModeController.text = profile.inputMode;
    _launchCommandController.text = profile.launch.command ?? '';
    _launchFlagsController.text = profile.launch.flags.join(', ');

    // Populate pattern controllers.
    for (final entry in profile.patterns.entries) {
      _patternControllers[entry.key] =
          TextEditingController(text: entry.value ?? '');
    }

    // Populate state config controllers.
    for (final entry in profile.states.entries) {
      _stateControllers[entry.key] = _StateConfigControllers(
        indicator: TextEditingController(text: entry.value.indicator),
        report: entry.value.report,
        priority: TextEditingController(text: entry.value.priority ?? ''),
      );
    }

    // Populate report template controllers.
    for (final entry in profile.reportTemplates.entries) {
      _templateControllers[entry.key] =
          TextEditingController(text: entry.value);
    }

    setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _typeController.dispose();
    _inputModeController.dispose();
    _launchCommandController.dispose();
    _launchFlagsController.dispose();
    for (final c in _patternControllers.values) {
      c.dispose();
    }
    for (final c in _stateControllers.values) {
      c.dispose();
    }
    for (final c in _templateControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  EngineProfile _buildProfile() {
    final flags = _launchFlagsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final patterns = <String, String?>{};
    for (final entry in _patternControllers.entries) {
      final value = entry.value.text.trim();
      patterns[entry.key] = value.isEmpty ? null : value;
    }

    final states = <String, StateConfig>{};
    for (final entry in _stateControllers.entries) {
      final priority = entry.value.priority.text.trim();
      states[entry.key] = StateConfig(
        indicator: entry.value.indicator.text.trim(),
        report: entry.value.report,
        priority: priority.isEmpty ? null : priority,
      );
    }

    final templates = <String, String>{};
    for (final entry in _templateControllers.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) {
        templates[entry.key] = value;
      }
    }

    return EngineProfile(
      name: _nameController.text.trim(),
      displayName: _displayNameController.text.trim(),
      type: _typeController.text.trim(),
      inputMode: _inputModeController.text.trim(),
      launch: LaunchConfig(
        command: _launchCommandController.text.trim().isEmpty
            ? null
            : _launchCommandController.text.trim(),
        flags: flags,
      ),
      patterns: patterns,
      states: states,
      reportTemplates: templates,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final profile = _buildProfile();
      final repo = ref.read(engineProfileRepositoryProvider);
      await repo.save(profile);
      ref.invalidate(allEngineProfilesProvider);
      ref.invalidate(userProfileNamesProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: _kErrorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurfaceColor,
        title: const Text(
          'Delete Profile',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${_displayNameController.text}"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final repo = ref.read(engineProfileRepositoryProvider);
    await repo.delete(_nameController.text);
    ref.invalidate(allEngineProfilesProvider);
    ref.invalidate(userProfileNamesProvider);

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _exportProfile() async {
    final profile = _buildProfile();
    final repo = ref.read(engineProfileRepositoryProvider);
    final json = repo.export(profile);
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile JSON copied to clipboard'),
          backgroundColor: _kSurfaceColor,
        ),
      );
    }
  }

  void _addPattern() {
    final name = 'pattern_${_patternControllers.length + 1}';
    setState(() {
      _patternControllers[name] = TextEditingController();
    });
  }

  void _removePattern(String key) {
    setState(() {
      _patternControllers.remove(key)?.dispose();
    });
  }

  void _addState() {
    final name = 'state_${_stateControllers.length + 1}';
    setState(() {
      _stateControllers[name] = _StateConfigControllers(
        indicator: TextEditingController(),
        report: false,
        priority: TextEditingController(),
      );
    });
  }

  void _removeState(String key) {
    setState(() {
      _stateControllers.remove(key)?.dispose();
    });
  }

  void _addTemplate() {
    final name = 'template_${_templateControllers.length + 1}';
    setState(() {
      _templateControllers[name] = TextEditingController();
    });
  }

  void _removeTemplate(String key) {
    setState(() {
      _templateControllers.remove(key)?.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew
        ? 'New Profile'
        : _isReadOnly
            ? _displayNameController.text.isEmpty
                ? 'Profile'
                : _displayNameController.text
            : 'Edit Profile';

    return Scaffold(
      backgroundColor: _kBgColor,
      appBar: AppBar(
        backgroundColor: _kBgColor,
        foregroundColor: _kTextPrimary,
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
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 20),
              onPressed: _exportProfile,
              tooltip: 'Export profile',
            ),
          if (!_isNew && !_isBundled)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20,
                  color: Colors.redAccent),
              onPressed: _delete,
              tooltip: 'Delete profile',
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              if (_isReadOnly)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kAccentColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kAccentColor.withAlpha(50)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, color: _kAccentColor, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bundled profile (read-only). Duplicate to customize.',
                          style: TextStyle(color: _kAccentColor, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              _buildSectionHeader('GENERAL'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _nameController,
                label: 'Name',
                hint: 'my-engine',
                readOnly: _isReadOnly || (!_isNew),
                validator: _requiredValidator('Name is required'),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _displayNameController,
                label: 'Display Name',
                hint: 'My Engine',
                readOnly: _isReadOnly,
                validator: _requiredValidator('Display name is required'),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _typeController,
                label: 'Type',
                hint: 'chat-tui',
                readOnly: _isReadOnly,
                validator: _requiredValidator('Type is required'),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _inputModeController,
                label: 'Input Mode',
                hint: 'natural_language',
                readOnly: _isReadOnly,
                validator: _requiredValidator('Input mode is required'),
              ),
              const SizedBox(height: 24),
              _buildSectionHeader('LAUNCH'),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _launchCommandController,
                label: 'Command',
                hint: 'claude',
                readOnly: _isReadOnly,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _launchFlagsController,
                label: 'Flags (comma-separated)',
                hint: '--flag1, --flag2',
                readOnly: _isReadOnly,
              ),
              const SizedBox(height: 24),
              _buildPatternsSection(),
              const SizedBox(height: 24),
              _buildStatesSection(),
              const SizedBox(height: 24),
              _buildTemplatesSection(),
              const SizedBox(height: 24),
              if (_isReadOnly) ...[
                _buildDuplicateButton(),
              ] else ...[
                _buildSaveButton(),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 13,
        fontFamily: 'JetBrains Mono',
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _kTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          validator: readOnly ? null : validator,
          style: TextStyle(
            color: readOnly ? Colors.white54 : _kTextPrimary,
            fontFamily: 'JetBrains Mono',
            fontSize: 13,
          ),
          cursorColor: _kAccentColor,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: _kTextMuted,
              fontFamily: 'JetBrains Mono',
              fontSize: 13,
            ),
            filled: true,
            fillColor: _kSurfaceColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kSurfaceBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kSurfaceBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kAccentColor, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kErrorRed),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _kErrorRed, width: 1.5),
            ),
            errorStyle: const TextStyle(color: _kErrorRed, fontSize: 12),
          ),
        ),
      ],
    );
  }

  // -- Patterns section -------------------------------------------------------

  Widget _buildPatternsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('PATTERNS'),
            if (!_isReadOnly)
              IconButton(
                icon: const Icon(Icons.add, color: _kAccentColor, size: 20),
                onPressed: _addPattern,
                tooltip: 'Add pattern',
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_patternControllers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No patterns defined',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ),
        ..._patternControllers.entries.map((entry) {
          return _KeyValueRow(
            keyLabel: entry.key,
            controller: entry.value,
            readOnly: _isReadOnly,
            onRemove: _isReadOnly ? null : () => _removePattern(entry.key),
            onKeyChanged: _isReadOnly
                ? null
                : (newKey) {
                    if (newKey == entry.key || newKey.isEmpty) return;
                    setState(() {
                      final ctrl = _patternControllers.remove(entry.key);
                      if (ctrl != null) _patternControllers[newKey] = ctrl;
                    });
                  },
            hint: 'Regex pattern',
          );
        }),
      ],
    );
  }

  // -- States section ---------------------------------------------------------

  Widget _buildStatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('STATES'),
            if (!_isReadOnly)
              IconButton(
                icon: const Icon(Icons.add, color: _kAccentColor, size: 20),
                onPressed: _addState,
                tooltip: 'Add state',
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_stateControllers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No states defined',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ),
        ..._stateControllers.entries.map((entry) {
          return _StateConfigCard(
            stateName: entry.key,
            controllers: entry.value,
            readOnly: _isReadOnly,
            onRemove: _isReadOnly ? null : () => _removeState(entry.key),
            onNameChanged: _isReadOnly
                ? null
                : (newName) {
                    if (newName == entry.key || newName.isEmpty) return;
                    setState(() {
                      final ctrl = _stateControllers.remove(entry.key);
                      if (ctrl != null) _stateControllers[newName] = ctrl;
                    });
                  },
            onReportChanged: _isReadOnly
                ? null
                : (value) {
                    setState(() {
                      entry.value.report = value;
                    });
                  },
          );
        }),
      ],
    );
  }

  // -- Report templates section -----------------------------------------------

  Widget _buildTemplatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('REPORT TEMPLATES'),
            if (!_isReadOnly)
              IconButton(
                icon: const Icon(Icons.add, color: _kAccentColor, size: 20),
                onPressed: _addTemplate,
                tooltip: 'Add template',
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_templateControllers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No templates defined',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ),
        ..._templateControllers.entries.map((entry) {
          return _KeyValueRow(
            keyLabel: entry.key,
            controller: entry.value,
            readOnly: _isReadOnly,
            onRemove: _isReadOnly ? null : () => _removeTemplate(entry.key),
            onKeyChanged: _isReadOnly
                ? null
                : (newKey) {
                    if (newKey == entry.key || newKey.isEmpty) return;
                    setState(() {
                      final ctrl = _templateControllers.remove(entry.key);
                      if (ctrl != null) _templateControllers[newKey] = ctrl;
                    });
                  },
            hint: 'Template text',
          );
        }),
      ],
    );
  }

  // -- Action buttons ---------------------------------------------------------

  Widget _buildSaveButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAccentColor,
          foregroundColor: _kBgColor,
          disabledBackgroundColor: _kAccentColor.withAlpha(102),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kBgColor,
                ),
              )
            : Text(
                _isNew ? 'Create Profile' : 'Save Changes',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildDuplicateButton() {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () {
          // Pre-populate a new profile with this profile's data.
          setState(() {
            _isNew = true;
            _isBundled = false;
            _isReadOnly = false;
            _nameController.text = '${_nameController.text}-custom';
            _displayNameController.text =
                '${_displayNameController.text} (Custom)';
          });
        },
        icon: const Icon(Icons.copy_outlined, size: 18),
        label: const Text(
          'Duplicate as Custom Profile',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _kAccentColor,
          side: const BorderSide(color: _kAccentColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
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

// -- Helper widgets -----------------------------------------------------------

/// A key-value row for patterns and templates.
class _KeyValueRow extends StatelessWidget {
  final String keyLabel;
  final TextEditingController controller;
  final bool readOnly;
  final VoidCallback? onRemove;
  final ValueChanged<String>? onKeyChanged;
  final String? hint;

  const _KeyValueRow({
    required this.keyLabel,
    required this.controller,
    required this.readOnly,
    this.onRemove,
    this.onKeyChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: _kSurfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kSurfaceBorder),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: readOnly
                      ? Text(
                          keyLabel,
                          style: const TextStyle(
                            color: _kAccentColor,
                            fontSize: 12,
                            fontFamily: 'JetBrains Mono',
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : _EditableLabel(
                          initialValue: keyLabel,
                          onChanged: onKeyChanged,
                        ),
                ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.redAccent, size: 18),
                    onPressed: onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: controller,
              readOnly: readOnly,
              style: TextStyle(
                color: readOnly ? Colors.white54 : Colors.white,
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
              ),
              cursorColor: _kAccentColor,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: _kTextMuted, fontSize: 12),
                filled: true,
                fillColor: _kBgColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editable inline label for key names.
class _EditableLabel extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String>? onChanged;

  const _EditableLabel({
    required this.initialValue,
    this.onChanged,
  });

  @override
  State<_EditableLabel> createState() => _EditableLabelState();
}

class _EditableLabelState extends State<_EditableLabel> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      onFieldSubmitted: widget.onChanged,
      style: const TextStyle(
        color: _kAccentColor,
        fontSize: 12,
        fontFamily: 'JetBrains Mono',
        fontWeight: FontWeight.w600,
      ),
      cursorColor: _kAccentColor,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 4),
        border: InputBorder.none,
      ),
    );
  }
}

/// Card for editing a state configuration entry.
class _StateConfigCard extends StatelessWidget {
  final String stateName;
  final _StateConfigControllers controllers;
  final bool readOnly;
  final VoidCallback? onRemove;
  final ValueChanged<String>? onNameChanged;
  final ValueChanged<bool>? onReportChanged;

  const _StateConfigCard({
    required this.stateName,
    required this.controllers,
    required this.readOnly,
    this.onRemove,
    this.onNameChanged,
    this.onReportChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: _kSurfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kSurfaceBorder),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: readOnly
                      ? Text(
                          stateName,
                          style: const TextStyle(
                            color: _kAccentColor,
                            fontSize: 12,
                            fontFamily: 'JetBrains Mono',
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : _EditableLabel(
                          initialValue: stateName,
                          onChanged: onNameChanged,
                        ),
                ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.redAccent, size: 18),
                    onPressed: onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _miniField(
              controller: controllers.indicator,
              label: 'Indicator',
              readOnly: readOnly,
            ),
            const SizedBox(height: 8),
            _miniField(
              controller: controllers.priority,
              label: 'Priority',
              readOnly: readOnly,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Report',
                  style: TextStyle(
                    color: _kTextSecondary,
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
                const Spacer(),
                Switch.adaptive(
                  value: controllers.report,
                  onChanged: readOnly ? null : onReportChanged,
                  activeColor: _kAccentColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniField({
    required TextEditingController controller,
    required String label,
    required bool readOnly,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            readOnly: readOnly,
            style: TextStyle(
              color: readOnly ? Colors.white54 : Colors.white,
              fontFamily: 'JetBrains Mono',
              fontSize: 12,
            ),
            cursorColor: _kAccentColor,
            decoration: InputDecoration(
              filled: true,
              fillColor: _kBgColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// Grouped controllers for a state configuration entry.
class _StateConfigControllers {
  final TextEditingController indicator;
  bool report;
  final TextEditingController priority;

  _StateConfigControllers({
    required this.indicator,
    required this.report,
    required this.priority,
  });

  void dispose() {
    indicator.dispose();
    priority.dispose();
  }
}
