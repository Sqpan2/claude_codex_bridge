import '../../pairing/gateway_pairing.dart';

String projectHomeGatewayProfileKey(GatewayPairedHost profile) {
  return '${profile.profile.hostId}/${profile.profile.deviceId}';
}

String projectHomeGatewayProfileLabel(GatewayPairedHost profile) {
  final route = profile.profile.routeProvider.kind.wireName;
  final relayMode = profile.profile.routeProvider.relayMode;
  final routeLabel = route == 'relay' && relayMode != null
      ? '$route/${relayMode.wireName}'
      : route;
  return '${profile.profile.hostId} / ${profile.profile.deviceId} / $routeLabel';
}

/// Short human-facing name of a paired computer, used where several hosts are
/// listed together. The pairing contract carries no computer name, so the
/// paired project id is preferred and an abbreviated host id is the fallback.
String projectHomeGatewayProfileHostName(GatewayPairedHost profile) {
  final projectId = profile.projectId?.trim() ?? '';
  if (projectId.isNotEmpty) {
    return projectId;
  }
  final hostId = profile.profile.hostId.trim();
  return hostId.length <= 12 ? hostId : '${hostId.substring(0, 12)}…';
}

List<GatewayPairedHost> sortProjectHomeGatewayProfiles(
  Iterable<GatewayPairedHost> profiles,
) {
  return [...profiles]..sort(
    (a, b) => projectHomeGatewayProfileLabel(
      a,
    ).compareTo(projectHomeGatewayProfileLabel(b)),
  );
}

List<GatewayPairedHost> mergeProjectHomeGatewayProfiles(
  Iterable<GatewayPairedHost> profiles,
  GatewayPairedHost paired,
) {
  final key = projectHomeGatewayProfileKey(paired);
  return sortProjectHomeGatewayProfiles([
    for (final profile in profiles)
      if (projectHomeGatewayProfileKey(profile) != key) profile,
    paired,
  ]);
}
