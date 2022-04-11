abstract class IBundleState {
  Set<String> get installedBundleKeys;

  const factory IBundleState.empty() = EmptyBundleState;
}

class EmptyBundleState implements IBundleState {
  @override
  Set<String> get installedBundleKeys => {};

  const EmptyBundleState();
}
