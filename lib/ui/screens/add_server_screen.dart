import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/data/repositories/server_repository.dart';
import 'package:murminal/data/services/ssh_service.dart';

/// Authentication type selection for the form.
enum _AuthType { sshKey, password }

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textSecondary = Color(0xFF94A3B8);
const _textMuted = Color(0xFF475569);
const _surfaceBorder = Color(0xFF334155);
const _errorRed = Color(0xFFEF4444);
const _successGreen = Color(0xFF22C55E);

/// Screen for adding or editing an SSH server configuration.
///
/// When [existingConfig] is provided, the form is pre-populated for editing.
class AddServerScreen extends StatefulWidget {
  /// The server repository for persistence.
  final ServerRepository repository;

  /// Optional existing configuration for edit mode.
  final ServerConfig? existingConfig;

  const AddServerScreen({
    super.key,
    required this.repository,
    this.existingConfig,
  });

  @override
  State<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends State<AddServerScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _labelController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _keyPathController;
  late final TextEditingController _passphraseController;

  _AuthType _authType = _AuthType.sshKey;
  bool _isTesting = false;
  bool _isSaving = false;
  bool _obscurePassword = true;
  _TestResult? _testResult;

  bool get _isEditing => widget.existingConfig != null;

  @override
  void initState() {
    super.initState();
    final config = widget.existingConfig;

    _labelController = TextEditingController(text: config?.label ?? '');
    _hostController = TextEditingController(text: config?.host ?? '');
    _portController = TextEditingController(
      text: (config?.port ?? 22).toString(),
    );
    _usernameController = TextEditingController(text: config?.username ?? '');
    _passwordController = TextEditingController();
    _keyPathController = TextEditingController();
    _passphraseController = TextEditingController();

    if (config != null) {
      switch (config.auth) {
        case PasswordAuth(password: final pw):
          _authType = _AuthType.password;
          _passwordController.text = pw;
        case KeyAuth(
            privateKeyPath: final path,
            passphrase: final passphrase,
          ):
          _authType = _AuthType.sshKey;
          _keyPathController.text = path;
          if (passphrase != null) {
            _passphraseController.text = passphrase;
          }
      }
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _keyPathController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  AuthMethod _buildAuthMethod() {
    if (_authType == _AuthType.password) {
      return PasswordAuth(password: _passwordController.text);
    }
    return KeyAuth(
      privateKeyPath: _keyPathController.text,
      passphrase: _passphraseController.text.isEmpty
          ? null
          : _passphraseController.text,
    );
  }

  ServerConfig _buildConfig() {
    final existing = widget.existingConfig;
    return ServerConfig(
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      label: _labelController.text.trim(),
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text) ?? 22,
      username: _usernameController.text.trim(),
      auth: _buildAuthMethod(),
      createdAt: existing?.createdAt ?? DateTime.now(),
      lastConnectedAt: existing?.lastConnectedAt,
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final sshService = SshService();
    try {
      final config = _buildConfig();
      await sshService.connect(config).timeout(
        const Duration(seconds: 10),
      );
      await sshService.disconnect();
      setState(() {
        _testResult = _TestResult.success;
      });
    } on Exception catch (e) {
      setState(() {
        _testResult = _TestResult.failure(e.toString());
      });
    } finally {
      sshService.dispose();
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _saveServer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final config = _buildConfig();
      await widget.repository.save(config);

      if (mounted) {
        Navigator.of(context).pop(config);
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: _errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickKeyFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.single.path;
      if (path != null) {
        _keyPathController.text = path;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _textPrimary,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 12),
              Icon(Icons.chevron_left, color: _textSecondary, size: 20),
              Text(
                'Servers',
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        leadingWidth: 110,
        title: Text(
          _isEditing ? 'EDIT SERVER' : 'ADD SERVER',
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: false,
        actions: const [SizedBox(width: 16)],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              _buildTextField(
                controller: _labelController,
                label: 'Label',
                hint: 'e.g. mac-mini',
                validator: _requiredValidator('Label is required'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _hostController,
                label: 'Host',
                hint: '192.168.1.10 or hostname',
                validator: _requiredValidator('Host is required'),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _portController,
                label: 'Port',
                hint: '22',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Port is required';
                  }
                  final port = int.tryParse(value);
                  if (port == null || port < 1 || port > 65535) {
                    return 'Enter a valid port (1-65535)';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _usernameController,
                label: 'Username',
                hint: 'root',
                validator: _requiredValidator('Username is required'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 24),
              _buildAuthSelector(),
              const SizedBox(height: 20),
              if (_authType == _AuthType.sshKey) ...[
                _buildKeyFileField(),
              ] else ...[
                _buildPasswordField(),
              ],
              const SizedBox(height: 32),
              _buildTestConnectionResult(),
              _buildTestConnectionButton(),
              const SizedBox(height: 12),
              _buildSaveButton(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a labeled text input field with dark surface styling.
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool obscureText = false,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          obscureText: obscureText,
          textInputAction: textInputAction,
          style: const TextStyle(
            color: _textPrimary,
            fontFamily: 'JetBrains Mono',
            fontSize: 14,
          ),
          cursorColor: _accent,
          decoration: _inputDecoration(hint: hint, suffixIcon: suffixIcon),
        ),
      ],
    );
  }

  /// Shared input decoration matching the wireframe dark input style.
  InputDecoration _inputDecoration({String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: _textMuted,
        fontFamily: 'JetBrains Mono',
        fontSize: 14,
      ),
      filled: true,
      fillColor: _surface,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    );
  }

  /// Builds the SSH Key / Password authentication toggle.
  Widget _buildAuthSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Authentication',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _surfaceBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildAuthOption(
                  label: 'SSH Key',
                  value: _AuthType.sshKey,
                  isFirst: true,
                ),
              ),
              Expanded(
                child: _buildAuthOption(
                  label: 'Password',
                  value: _AuthType.password,
                  isFirst: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds a single auth toggle option pill.
  Widget _buildAuthOption({
    required String label,
    required _AuthType value,
    required bool isFirst,
  }) {
    final isSelected = _authType == value;

    return GestureDetector(
      onTap: () => setState(() {
        _authType = value;
        _testResult = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? _accent : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(6) : Radius.zero,
            right: isFirst ? Radius.zero : const Radius.circular(6),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _background : _textMuted,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  /// Builds the key file field with an integrated file picker icon.
  Widget _buildKeyFileField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Key File',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _keyPathController,
          readOnly: true,
          onTap: _pickKeyFile,
          style: const TextStyle(
            color: _textPrimary,
            fontFamily: 'JetBrains Mono',
            fontSize: 14,
          ),
          cursorColor: _accent,
          decoration: _inputDecoration(
            hint: '~/.ssh/id_ed25519',
            suffixIcon: IconButton(
              icon: const Icon(Icons.folder_open, color: _textMuted, size: 20),
              onPressed: _pickKeyFile,
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Key file is required';
            }
            return null;
          },
        ),
      ],
    );
  }

  /// Builds the password field with a visibility toggle.
  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Password',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          style: const TextStyle(
            color: _textPrimary,
            fontFamily: 'JetBrains Mono',
            fontSize: 14,
          ),
          cursorColor: _accent,
          decoration: _inputDecoration(
            hint: 'Enter password',
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: _textMuted,
                size: 20,
              ),
              onPressed: () => setState(() {
                _obscurePassword = !_obscurePassword;
              }),
            ),
          ),
          validator: _requiredValidator('Password is required'),
        ),
      ],
    );
  }

  /// Displays the connection test result banner.
  Widget _buildTestConnectionResult() {
    final result = _testResult;
    if (result == null) return const SizedBox.shrink();

    final isSuccess = result == _TestResult.success;
    final color = isSuccess ? _successGreen : _errorRed;
    final icon = isSuccess ? Icons.check_circle_outline : Icons.error_outline;
    final message = isSuccess
        ? 'Connection successful'
        : 'Connection failed: ${(result as _TestFailure).message}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the outlined "Test Connection" button.
  Widget _buildTestConnectionButton() {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _isTesting ? null : _testConnection,
        icon: _isTesting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accent,
                ),
              )
            : const Icon(Icons.settings_ethernet, size: 18),
        label: Text(
          _isTesting ? 'Testing...' : 'Test Connection',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _accent,
          side: const BorderSide(color: _accent, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  /// Builds the filled "Save Server" button.
  Widget _buildSaveButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveServer,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: _background,
          disabledBackgroundColor: _accent.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _background,
                ),
              )
            : Text(
                _isEditing ? 'Save Changes' : 'Save Server',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
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

/// Result of an SSH connection test.
sealed class _TestResult {
  static const success = _TestSuccess();

  const _TestResult();

  factory _TestResult.failure(String message) = _TestFailure;
}

class _TestSuccess extends _TestResult {
  const _TestSuccess();
}

class _TestFailure extends _TestResult {
  final String message;

  const _TestFailure(this.message);
}
