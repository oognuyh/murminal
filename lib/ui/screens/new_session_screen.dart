import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/engine_profile.dart';
import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/models/worktree_info.dart';

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
/// specify a git repository path to browse worktrees, and launch a
/// tmux session in the selected worktree directory.
class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key});

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _workingDirController = TextEditingController();
  final _repoPathController = TextEditingController();
  final _newBranchController = TextEditingController();

  ServerConfig? _selectedServer;
  EngineProfile? _selectedEngine;
  bool _isCreating = false;

  /// Worktree state.
  List<WorktreeInfo> _worktrees = [];
  WorktreeInfo? _selectedWorktree;
  bool _isLoadingWorktrees = false;
  String? _worktreeError;
  bool _showNewWorktreeForm = false;
  bool _isCreatingWorktree = false;

  @override
  void dispose() {
    _workingDirController.dispose();
    _repoPathController.dispose();
    _newBranchController.dispose();
    super.dispose();
  }

  /// Fetch worktrees for the repository path entered by the user.
  Future<void> _fetchWorktrees() async {
    final repoPath = _repoPathController.text.trim();
    if (repoPath.isEmpty) {
      setState(() {
        _worktrees = [];
        _selectedWorktree = null;
        _worktreeError = null;
      });
      return;
    }

    setState(() {
      _isLoadingWorktrees = true;
      _worktreeError = null;
    });

    try {
      final worktreeService = ref.read(worktreeServiceProvider);
      final worktrees = await worktreeService.listWorktrees(repoPath);
      setState(() {
        _worktrees = worktrees;
        _selectedWorktree = null;
        _isLoadingWorktrees = false;
      });
    } on Exception catch (e) {
      setState(() {
        _worktrees = [];
        _selectedWorktree = null;
        _worktreeError = 'Failed to list worktrees: $e';
        _isLoadingWorktrees = false;
      });
    }
  }

  /// Create a new worktree from the branch name input.
  Future<void> _createNewWorktree() async {
    final repoPath = _repoPathController.text.trim();
    final branch = _newBranchController.text.trim();
    if (repoPath.isEmpty || branch.isEmpty) return;

    setState(() => _isCreatingWorktree = true);

    try {
      final worktreeService = ref.read(worktreeServiceProvider);
      final newWorktree =
          await worktreeService.createWorktree(repoPath, branch);

      // Refresh the list and select the newly created worktree.
      final worktrees = await worktreeService.listWorktrees(repoPath);
      setState(() {
        _worktrees = worktrees;
        _selectedWorktree = worktrees.firstWhere(
          (w) => w.branch == newWorktree.branch,
          orElse: () => newWorktree,
        );
        _showNewWorktreeForm = false;
        _newBranchController.clear();
        _isCreatingWorktree = false;
      });
    } on Exception catch (e) {
      setState(() => _isCreatingWorktree = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create worktree: $e'),
            backgroundColor: _errorRed,
          ),
        );
      }
    }
  }

  /// Resolve the effective working directory from worktree or manual input.
  String? get _effectiveWorkingDir {
    if (_selectedWorktree != null) {
      return _selectedWorktree!.path;
    }
    final manual = _workingDirController.text.trim();
    return manual.isNotEmpty ? manual : null;
  }

  Future<void> _createSession() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedServer == null || _selectedEngine == null) return;

    setState(() => _isCreating = true);

    try {
      final sessionService = ref.read(sessionServiceProvider);
      final engine = _selectedEngine!;
      final workingDir = _effectiveWorkingDir;

      // Build the launch command from the engine profile, prepending
      // a cd into the working directory when one is provided.
      String? launchCommand = engine.launch.command;
      if (workingDir != null && launchCommand != null) {
        launchCommand = 'cd $workingDir && $launchCommand';
      } else if (workingDir != null) {
        launchCommand = 'cd $workingDir';
      }

      await sessionService.createSession(
        serverId: _selectedServer!.id,
        engine: engine.name,
        name: '${engine.displayName}-${_selectedServer!.label}',
        launchCommand: launchCommand,
        worktreePath: _selectedWorktree?.path,
        worktreeBranch: _selectedWorktree?.branch,
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
              const SizedBox(height: 24),
              _buildSectionHeader('GIT WORKTREE'),
              const SizedBox(height: 8),
              _buildRepoPathField(),
              const SizedBox(height: 12),
              _buildWorktreeSelector(),
              const SizedBox(height: 24),
              _buildSectionHeader('MANUAL OVERRIDE'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _workingDirController,
                label: 'Working Directory',
                hint: '/home/user/project (optional)',
              ),
              if (_selectedWorktree != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Worktree selection overrides manual directory',
                    style: TextStyle(
                      color: _accent.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
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

  /// Builds a section header label.
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _accent,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        fontFamily: 'JetBrains Mono',
        letterSpacing: 1.5,
      ),
    );
  }

  /// Builds the git repository path field with a fetch button.
  Widget _buildRepoPathField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Git Repository',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _repoPathController,
                style: const TextStyle(
                  color: _textPrimary,
                  fontFamily: 'JetBrains Mono',
                  fontSize: 13,
                ),
                cursorColor: _accent,
                decoration: InputDecoration(
                  hintText: '/home/user/repo (optional)',
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
                ),
                onFieldSubmitted: (_) => _fetchWorktrees(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoadingWorktrees ? null : _fetchWorktrees,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _surface,
                  foregroundColor: _accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: _surfaceBorder),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _isLoadingWorktrees
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _accent,
                        ),
                      )
                    : const Icon(Icons.search, size: 20),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Builds the worktree dropdown and new worktree creation form.
  Widget _buildWorktreeSelector() {
    if (_worktreeError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _worktreeError!,
          style: const TextStyle(
            color: _errorRed,
            fontSize: 12,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      );
    }

    if (_worktrees.isEmpty && !_isLoadingWorktrees) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Worktree dropdown.
        _buildDropdown<WorktreeInfo>(
          label: 'Worktree',
          hint: 'Select a worktree',
          value: _selectedWorktree,
          items: _worktrees,
          itemLabel: (w) {
            final branch = w.branch ?? 'detached';
            final shortPath = w.path.split('/').last;
            return '$branch ($shortPath)';
          },
          onChanged: (value) => setState(() => _selectedWorktree = value),
        ),
        const SizedBox(height: 8),
        // New worktree toggle button.
        GestureDetector(
          onTap: () =>
              setState(() => _showNewWorktreeForm = !_showNewWorktreeForm),
          child: Row(
            children: [
              Icon(
                _showNewWorktreeForm ? Icons.remove : Icons.add,
                color: _accent,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                _showNewWorktreeForm
                    ? 'Cancel new worktree'
                    : 'Create new worktree',
                style: const TextStyle(
                  color: _accent,
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        // New worktree creation form.
        if (_showNewWorktreeForm) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _newBranchController,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontFamily: 'JetBrains Mono',
                    fontSize: 13,
                  ),
                  cursorColor: _accent,
                  decoration: InputDecoration(
                    hintText: 'Branch name',
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
                      borderSide:
                          const BorderSide(color: _accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isCreatingWorktree ? null : _createNewWorktree,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _background,
                    disabledBackgroundColor: _accent.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: _isCreatingWorktree
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _background,
                          ),
                        )
                      : const Text(
                          'Create',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ],
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
        onPressed: _isCreating ? null : _createSession,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _background,
          disabledBackgroundColor: _accent.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: _isCreating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _background,
                ),
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
