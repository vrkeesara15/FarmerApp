-- AN-005 store snapshot (stock turns, stockouts, credit ageing). Store managers: own store; cluster heads: own cluster.
{{ authorised_view('mart_store_snapshot', grain='store', scoped_roles=['cluster_head', 'store_manager']) }}
