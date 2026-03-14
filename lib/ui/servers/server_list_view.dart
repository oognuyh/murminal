import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murminal/core/providers.dart';
import 'package:murminal/data/models/server_config.dart';
import 'package:murminal/ui/screens/add_server_screen.dart';

/// Theme colors matching the app's dark slate design.
const _background = Color(0xFF0A0F1C);
const _surface = Color(0xFF1E293B);
const _accent = Color(0xFF22D3EE);
const _textPrimary = Color(0xFFFFFFFF);
const _textMuted = Color(0xFF64748B);
const _searchIcon = Color(0xFF475569);

/// Server list management screen.
///
/// Displays all registered servers grouped by connection status (Connected /
/// Saved) with search filtering, status indicators, and navigation to the
/// add/edit server screen.
class ServerListView extends ConsumerStatefulWidget {
  const ServerListView({super.key});

  @override
  ConsumerState<ServerListView> createState() => _ServerListViewState();
}

class _ServerListViewState extends ConsumerState<ServerListView> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filter servers by search query against label and host.
  List<ServerConfig> _filterServers(List<ServerConfig> servers) {
    if (_searchQuery.isEmpty) return servers;
    final query = _searchQuery.toLowerCase();
    return servers.where((s) {
      return s.label.toLowerCase().contains(query) ||
          s.host.toLowerCase().contains(query);
    }).toList();
  }

  /// Navigate to the add server screen and refresh list on return.
  Future<void> _navigateToAddServer() async {
    final repository = ref.read(serverRepositoryProvider);
    final result = await Navigator.of(context).push<ServerConfig>(
      MaterialPageRoute(
        builder: (_) => AddServerScreen(repository: repository),
      ),
    );
    if (result != null) {
      ref.invalidate(serverListProvider);
    }
  }

  /// Navigate to edit an existing server and refresh list on return.
  Future<void> _navigateToEditServer(ServerConfig config) async {
    final repository = ref.read(serverRepositoryProvider);
    final result = await Navigator.of(context).push<ServerConfig>(
      MaterialPageRoute(
        builder: (_) => AddServerScreen(
          repository: repository,
          existingConfig: config,
        ),
      ),
    );
    if (result != null) {
      ref.invalidate(serverListProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allServers = ref.watch(serverListProvider);
    final filtered = _filterServers(allServers);

    // Partition into connected (has lastConnectedAt) and saved (never connected).
    final connected = <ServerConfig>[];
    final saved = <ServerConfig>[];
    for (final server in filtered) {
      if (server.lastConnectedAt != null) {
        connected.add(server);
      } else {
        saved.add(server);
      }
    }

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              _buildHeader(),
              const SizedBox(height: 20),
              _buildSearchBar(),
              const SizedBox(height: 24),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(allServers.isEmpty)
                    : ListView(
                        children: [
                          if (connected.isNotEmpty) ...[
                            _buildSectionLabel('CONNECTED'),
                            const SizedBox(height: 12),
                            ...connected.map(_buildServerCard),
                          ],
                          if (connected.isNotEmpty && saved.isNotEmpty)
                            const SizedBox(height: 24),
                          if (saved.isNotEmpty) ...[
                            _buildSectionLabel('SAVED'),
                            const SizedBox(height: 12),
                            ...saved.map(_buildServerCard),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Title row with SERVERS heading and add button.
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'SERVERS',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFamily: 'JetBrains Mono',
            letterSpacing: 2,
          ),
        ),
        GestureDetector(
          onTap: _navigateToAddServer,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add,
              color: _accent,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  /// Search bar for filtering servers.
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: const TextStyle(
          color: _textPrimary,
          fontFamily: 'JetBrains Mono',
          fontSize: 13,
        ),
        cursorColor: _accent,
        decoration: const InputDecoration(
          hintText: 'Search servers...',
          hintStyle: TextStyle(
            color: _searchIcon,
            fontFamily: 'JetBrains Mono',
            fontSize: 13,
          ),
          prefixIcon: Icon(Icons.search, color: _searchIcon, size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  /// Section label for grouping (CONNECTED / SAVED).
  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: _textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        fontFamily: 'Inter',
        letterSpacing: 2,
      ),
    );
  }

  /// Individual server card with status indicator.
  Widget _buildServerCard(ServerConfig server) {
    final isConnected = server.lastConnectedAt != null;
    final statusColor = isConnected ? _accent : _searchIcon;
    final address = '${server.username}@${server.host}:${server.port}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _navigateToEditServer(server),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Status indicator dot.
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              // Server info.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.label,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      address,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              ),
              // Chevron right.
              const Icon(
                Icons.chevron_right,
                color: _textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Empty state when no servers match or none exist.
  Widget _buildEmptyState(bool noServersAtAll) {
    final message = noServersAtAll
        ? 'No servers added yet.\nTap + to add your first server.'
        : 'No servers match your search.';

    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _textMuted,
          fontSize: 14,
          fontFamily: 'JetBrains Mono',
          height: 1.6,
        ),
      ),
    );
  }
}
