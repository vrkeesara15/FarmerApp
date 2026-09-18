import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_api.dart';
import '../state/auth_flow.dart';

/// Who may use store mode (SPEC 1.2 / 2.6): store managers and accountants
/// run the counter; cluster heads look in read-only (and decide credit
/// approvals, S09); every other role, field officers included, never sees
/// it.
enum StoreRole {
  /// No store mode.
  none,

  /// Store manager: everything at their own store.
  manager,

  /// Accountant: sales, queue, day close; stock is read-only.
  accountant,

  /// Cluster head: read-only store mode plus credit approvals.
  clusterHead;

  /// Store mode is available at all.
  bool get hasStoreMode => this != none;

  /// Opens store mode straight after login (A04 -> S01).
  bool get opensStoreOnLogin => this == manager || this == accountant;

  /// Read-only viewer.
  bool get readOnly => this == clusterHead;

  /// POS sales (`POS_ROLES`).
  bool get canSell => this == manager || this == accountant;

  /// Order queue transitions.
  bool get canMoveQueue => this == manager || this == accountant;

  /// Goods receipt, transfer, write-off, adjustment (`STOCK_WRITE_ROLES`;
  /// the cluster head's write rights stay in the console for the pilot).
  bool get canMoveStock => this == manager;

  /// Day close (`CLOSE_ROLES`).
  bool get canCloseDay => this == manager || this == accountant;

  /// Credit approvals (`APPROVER_ROLES`).
  bool get canApproveCredit => this == clusterHead;

  /// Credit limits up to the manager cap (`CREDIT_LIMIT_ROLES`).
  bool get canSetCreditLimit => this == manager;
}

/// The store role for an API [role] name.
StoreRole storeRoleFor(String? role) => switch (role) {
  'store_manager' => StoreRole.manager,
  'accountant' => StoreRole.accountant,
  'cluster_head' => StoreRole.clusterHead,
  _ => StoreRole.none,
};

/// The signed-in user: the session from the login flow, else the stored one.
final FutureProvider<AuthUser?> storeUserProvider = FutureProvider<AuthUser?>((
  ref,
) async {
  final fromFlow = ref.watch(authFlowProvider.select((s) => s.session));
  if (fromFlow != null) return fromFlow.user;
  final stored = await ref.watch(tokenStoreProvider).read();
  return stored?.user;
});

/// The signed-in user's [StoreRole] ([StoreRole.none] until known).
final Provider<StoreRole> storeRoleProvider = Provider<StoreRole>(
  (ref) => storeRoleFor(ref.watch(storeUserProvider).value?.role),
);

/// Width at which store screens switch to two panes (tablet portrait is
/// 800 dp; phones stay single-pane).
const double storeTwoPaneBreakpoint = 700;

/// Whether [context] is wide enough for two panes.
bool isStoreTwoPane(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= storeTwoPaneBreakpoint;
