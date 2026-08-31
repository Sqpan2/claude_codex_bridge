import 'package:flutter/material.dart';

import '../../app/chat_background.dart';
import '../../l10n/ccb_mobile_localizations.dart';
import '../../pairing/gateway_pairing.dart';
import 'project_home_gateway_profiles.dart';
import 'project_home_multi_host_projects.dart';
import 'project_list.dart';

/// Aggregated project list across every paired computer. Each row is tagged with
/// its owning host so projects that share an id stay distinguishable.
class ProjectHomeMultiHostProjectListHost extends StatelessWidget {
  const ProjectHomeMultiHostProjectListHost({
    required this.result,
    required this.onRefreshProjects,
    required this.onOpenTerminal,
    required this.onOpenSettings,
    required this.onOpenProject,
    this.unreadProjectIds = const {},
    this.workingProjectIds = const {},
    super.key,
  });

  final ProjectHomeMultiHostProjectsResult result;
  final VoidCallback onRefreshProjects;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenSettings;
  final ValueChanged<ProjectHomeHostProject> onOpenProject;
  final Set<String> unreadProjectIds;
  final Set<String> workingProjectIds;

  @override
  Widget build(BuildContext context) {
    final strings = CcbMobileLocalizations.of(context);
    final hasBackground = ccbWorkspaceBackgroundEnabled(context);
    final scaffold = Scaffold(
      backgroundColor: hasBackground ? Colors.transparent : null,
      body: SafeArea(
        child: Padding(
          key: const ValueKey('multi-host-project-list-screen'),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              strings.hostsOnline(
                                result.onlineHostCount,
                                result.hostCount,
                              ),
                              key: const ValueKey(
                                'multi-host-project-list-summary',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          // A host that has not answered yet is not counted as
                          // online, so the count is marked as still settling.
                          if (result.catalogs.any((catalog) => catalog.pending))
                            const Padding(
                              key: ValueKey(
                                'multi-host-project-list-progress',
                              ),
                              padding: EdgeInsets.only(left: 8),
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('project-list-refresh-action'),
                    tooltip: strings.refreshProjects,
                    onPressed: onRefreshProjects,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    key: const ValueKey('project-list-terminal-action'),
                    tooltip: strings.openTerminal,
                    onPressed: onOpenTerminal,
                    icon: const Icon(Icons.terminal),
                  ),
                  IconButton(
                    key: const ValueKey('project-list-settings-action'),
                    tooltip: strings.settings,
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              Expanded(child: _buildBody(strings)),
            ],
          ),
        ),
      ),
    );
    return CcbWorkspaceBackground(child: scaffold);
  }

  /// Renders project rows first, then one row per unreachable computer so a host
  /// that fails to answer stays visible instead of silently disappearing.
  Widget _buildBody(CcbMobileLocalizations strings) {
    final offlineCatalogs = [
      for (final catalog in result.catalogs)
        if (catalog.offline) catalog,
    ];
    final pending = result.catalogs.any((catalog) => catalog.pending);
    if (result.entries.isEmpty && offlineCatalogs.isEmpty) {
      return Center(
        key: const ValueKey('multi-host-project-list-empty'),
        child:
            pending
                ? const CircularProgressIndicator()
                : Text(strings.noCcbProjectsFound),
      );
    }
    return ListView.separated(
      key: const ValueKey('multi-host-project-list'),
      itemCount: result.entries.length + offlineCatalogs.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= result.entries.length) {
          return _OfflineHostListTile(
            catalog: offlineCatalogs[index - result.entries.length],
          );
        }
        final entry = result.entries[index];
        return _MultiHostProjectListTile(
          entry: entry,
          hasUnreadTaskCompletion: unreadProjectIds.contains(entry.project.id),
          hasWorkingAgents:
              entry.project.hasWorkingAgents ||
              workingProjectIds.contains(entry.project.id),
          onOpen: () {
            onOpenProject(entry);
          },
        );
      },
    );
  }
}

/// One aggregated row. Carries a host chip so the owning computer is visible
/// without opening the project.
class _MultiHostProjectListTile extends StatelessWidget {
  const _MultiHostProjectListTile({
    required this.entry,
    required this.onOpen,
    required this.hasUnreadTaskCompletion,
    required this.hasWorkingAgents,
  });

  final ProjectHomeHostProject entry;
  final VoidCallback onOpen;
  final bool hasUnreadTaskCompletion;
  final bool hasWorkingAgents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = entry.project;
    final root = project.root.trim();
    final health = project.health.trim();
    return ProjectWorkingRowHighlight(
      projectId: project.id,
      hasWorkingAgents: hasWorkingAgents,
      child: ListTile(
        key: ValueKey('multi-host-project-open-${entry.key}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ProjectAttentionAvatar(
          projectId: project.id,
          favorite: project.favorite,
          hasUnreadTaskCompletion: hasUnreadTaskCompletion,
          hasWorkingAgents: hasWorkingAgents,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                project.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 8),
            _HostChip(profile: entry.profile),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (root.isNotEmpty)
              Text(root, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (health.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                health,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

/// Placeholder row for a paired computer that did not answer the catalog
/// request, so the aggregated list still accounts for every host.
class _OfflineHostListTile extends StatelessWidget {
  const _OfflineHostListTile({required this.catalog});

  final ProjectHomeHostCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = CcbMobileLocalizations.of(context);
    return ListTile(
      key: ValueKey(
        'multi-host-offline-${projectHomeGatewayProfileKey(catalog.profile)}',
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(
        Icons.cloud_off_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        projectHomeGatewayProfileHostName(catalog.profile),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        strings.hostOffline,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Compact label of the computer that owns a project row.
class _HostChip extends StatelessWidget {
  const _HostChip({required this.profile});

  final GatewayPairedHost profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        projectHomeGatewayProfileHostName(profile),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
