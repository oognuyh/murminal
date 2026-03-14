import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

import 'package:murminal/data/models/ssh_key.dart';

/// Manages SSH key pairs with iOS Keychain storage via flutter_secure_storage.
///
/// Keys are stored as:
///   - `ssh_key_private:<id>` → PEM-encoded private key
///   - `ssh_keys_index` → JSON list of [SshKey] metadata
class SshKeyService {
  final FlutterSecureStorage _storage;

  /// Storage key for the metadata index.
  static const _indexKey = 'ssh_keys_index';

  /// Prefix for private key storage entries.
  static const _privateKeyPrefix = 'ssh_key_private:';

  SshKeyService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Generate a new Ed25519 SSH key pair.
  ///
  /// Returns the created [SshKey] with its public key in OpenSSH format.
  /// The private key is stored in the Keychain automatically.
  Future<SshKey> generateKey({required String name}) async {
    final signingKey = nacl.SigningKey.generate();
    final publicKeyBytes =
        Uint8List.fromList(signingKey.verifyKey.asTypedList);
    final privateKeyBytes = Uint8List.fromList(signingKey.asTypedList);

    final keyPair = OpenSSHEd25519KeyPair(
      publicKeyBytes,
      privateKeyBytes,
      name,
    );

    final pem = keyPair.toPem();
    final publicKeyEncoded = _formatPublicKey(publicKeyBytes, name);

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final sshKey = SshKey(
      id: id,
      name: name,
      publicKey: publicKeyEncoded,
      type: SshKeyType.ed25519,
      createdAt: DateTime.now(),
    );

    await _storePrivateKey(id, pem);
    await _addToIndex(sshKey);

    return sshKey;
  }

  /// Import an existing private key from PEM content.
  ///
  /// Parses the PEM to extract the public key and stores both
  /// the private key and metadata in the Keychain.
  Future<SshKey> importKey({
    required String name,
    required String pemContent,
    String? passphrase,
  }) async {
    final keyPairs = SSHKeyPair.fromPem(pemContent, passphrase);
    if (keyPairs.isEmpty) {
      throw ArgumentError('No valid key pairs found in PEM content');
    }

    final keyPair = keyPairs.first;
    final publicKey = keyPair.toPublicKey();
    final publicKeyEncoded =
        '${keyPair.type} ${base64Encode(publicKey.encode())} $name';

    final keyType = _resolveKeyType(keyPair);

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final sshKey = SshKey(
      id: id,
      name: name,
      publicKey: publicKeyEncoded,
      type: keyType,
      createdAt: DateTime.now(),
    );

    await _storePrivateKey(id, pemContent);
    await _addToIndex(sshKey);

    return sshKey;
  }

  /// List all stored SSH keys.
  Future<List<SshKey>> listKeys() async {
    return _loadIndex();
  }

  /// Delete a stored SSH key by its ID.
  ///
  /// Removes both the private key and the metadata entry.
  Future<void> deleteKey(String id) async {
    await _storage.delete(key: '$_privateKeyPrefix$id');
    await _removeFromIndex(id);
  }

  /// Retrieve the PEM-encoded private key for the given key ID.
  ///
  /// Returns null if the key is not found.
  Future<String?> getPrivateKey(String id) async {
    return _storage.read(key: '$_privateKeyPrefix$id');
  }

  /// Get dartssh2 [SSHKeyPair] instances for authentication.
  Future<List<SSHKeyPair>> getKeyPairs(String id) async {
    final pem = await getPrivateKey(id);
    if (pem == null) {
      throw StateError('Private key not found for id: $id');
    }
    return SSHKeyPair.fromPem(pem);
  }

  // -- Private helpers --

  Future<void> _storePrivateKey(String id, String pem) async {
    await _storage.write(key: '$_privateKeyPrefix$id', value: pem);
  }

  Future<List<SshKey>> _loadIndex() async {
    final raw = await _storage.read(key: _indexKey);
    if (raw == null || raw.isEmpty) return [];

    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => SshKey.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveIndex(List<SshKey> keys) async {
    final encoded = jsonEncode(keys.map((k) => k.toJson()).toList());
    await _storage.write(key: _indexKey, value: encoded);
  }

  Future<void> _addToIndex(SshKey key) async {
    final keys = await _loadIndex();
    keys.add(key);
    await _saveIndex(keys);
  }

  Future<void> _removeFromIndex(String id) async {
    final keys = await _loadIndex();
    keys.removeWhere((k) => k.id == id);
    await _saveIndex(keys);
  }

  /// Format an Ed25519 public key in OpenSSH authorized_keys format.
  String _formatPublicKey(Uint8List publicKeyBytes, String comment) {
    // OpenSSH wire format: [length][type-string][length][key-bytes]
    final typeBytes = utf8.encode('ssh-ed25519');
    final buffer = BytesBuilder();

    // Write type string with 4-byte big-endian length prefix.
    buffer.add(_uint32BigEndian(typeBytes.length));
    buffer.add(typeBytes);

    // Write public key bytes with 4-byte big-endian length prefix.
    buffer.add(_uint32BigEndian(publicKeyBytes.length));
    buffer.add(publicKeyBytes);

    final encoded = base64Encode(buffer.toBytes());
    return 'ssh-ed25519 $encoded $comment';
  }

  SshKeyType _resolveKeyType(SSHKeyPair keyPair) {
    if (keyPair.type == 'ssh-ed25519') return SshKeyType.ed25519;
    // Only Ed25519 is supported for now; imported keys of other types
    // still function but are labeled ed25519 as a fallback.
    return SshKeyType.ed25519;
  }

  Uint8List _uint32BigEndian(int value) {
    return Uint8List(4)
      ..[0] = (value >> 24) & 0xFF
      ..[1] = (value >> 16) & 0xFF
      ..[2] = (value >> 8) & 0xFF
      ..[3] = value & 0xFF;
  }
}
