import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/models/server_config.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8);
const _textMuted = Color(0xFF475569);
const _surfaceBorder = Color(0xFF334155);
const _errorRed = Color(0xFFEF4444);

/// Screen for creating a new Murminal session.
///
/// Allows the user to select a server and engine profile, optionally
/// specify a working directory, and launch a tmux session.
class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _workingDirController = TextEditingController();

  ServerConfig? _selectedServer;
  EngineProfile? _selectedEngine;
  bool _isCreating = false;
  bool _isConnecting = false;

  @override
  void dispose() {
    _workingDirController.dispose();
    super.dispose();
  }

  Future<void> _createSession() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedServer == null || _selectedEngine == null) return;

    final server = _selectedServer!;
    final engine = _selectedEngine!;

    // Step 1: Ensure the server is connected via the pool.
    setState(() => _isConnecting = true);

    try {
      final pool = ref.read(sshConnectionPoolProvider);

      // Register config so the pool knows how to connect.
      pool.register(server);

      // Establish (or reuse) the SSH connection.
      await pool.getConnection(server.id);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to ${server.label}: $e'),
            backgroundColor: _errorRed,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _isCreating = true;
      });
    }

    // Step 2: Create the session via the pool-backed service.
    try {
      final sessionService =
          await ref.read(sessionServiceProvider(server.id).future);
      final workingDir = _workingDirController.text.trim();

      // Build the launch command from the engine profile, prepending
      // a cd into the working directory when one is provided.
      String? launchCommand = engine.launch.command;
      if (workingDir.isNotEmpty && launchCommand != null) {
        launchCommand = 'cd $workingDir && $launchCommand';
      } else if (workingDir.isNotEmpty) {
        launchCommand = 'cd $workingDir';
      }

      await sessionService.createSession(
        serverId: server.id,
        engine: engine.name,
        name: '${engine.displayName}-${server.label}',
        launchCommand: launchCommand,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create session: $e'),
            backgroundColor: _errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serverListProvider);
    final engines = ref.watch(engineRegistryProvider).profiles;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _textPrimary,
        elevation: 0,
        title: const Text(
          'NEW SESSION',
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 18,
            letterSpacing: 1,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              _buildDropdown<ServerConfig>(
                label: 'Server',
                hint: 'Select a server',
                value: _selectedServer,
                items: servers,
                itemLabel: (s) => s.label,
                onChanged: (value) => setState(() => _selectedServer = value),
                validator: (value) =>
                    value == null ? 'Server is required' : null,
              ),
              const SizedBox(height: 16),
              _buildDropdown<EngineProfile>(
                label: 'Engine',
                hint: 'Select an engine',
                value: _selectedEngine,
                items: engines,
                itemLabel: (e) => e.displayName,
                onChanged: (value) => setState(() => _selectedEngine = value),
                validator: (value) =>
                    value == null ? 'Engine is required' : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _workingDirController,
                label: 'Working Directory',
                hint: '/home/user/project (optional)',
              ),
              const SizedBox(height: 32),
              _buildCreateButton(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a themed dropdown field for selecting from a list of items.
  Widget _buildDropdown<T>({
    required String label,
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
    FormFieldValidator<T>? validator,
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
        DropdownButtonFormField<T>(
          value: value,
          validator: validator,
          onChanged: onChanged,
          isExpanded: true,
          dropdownColor: _surface,
          style: const TextStyle(
            color: _textPrimary,
            fontFamily: 'JetBrains Mono',
            fontSize: 13,
          ),
          icon: const Icon(Icons.keyboard_arrow_down, color: _textMuted),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: _textMuted,
              fontFamily: 'JetBrains Mono',
              fontSize: 13,
            ),
            filled: true,
            fillColor: _surface,
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
              borderSide: const BorderSide(color: _errorRed),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _errorRed, width: 1.5),
            ),
            errorStyle: const TextStyle(color: _errorRed, fontSize: 12),
          ),
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(itemLabel(item)),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Builds a themed text field matching the app's dark slate design.
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
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
          style: const TextStyle(
            color: _textPrimary,
            fontFamily: 'JetBrains Mono',
            fontSize: 13,
          ),
          cursorColor: _accent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: _textMuted,
              fontFamily: 'JetBrains Mono',
              fontSize: 13,
            ),
            filled: true,
            fillColor: _surface,
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
              borderSide: const BorderSide(color: _errorRed),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _errorRed, width: 1.5),
            ),
            errorStyle: const TextStyle(color: _errorRed, fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// Builds the primary create session button.
  Widget _buildCreateButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: (_isConnecting || _isCreating) ? null : _createSession,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _background,
          disabledBackgroundColor: _accent.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: (_isConnecting || _isCreating)
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _background,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isConnecting ? 'Connecting...' : 'Creating...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              )
            : const Text(
                'Create Session',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}
