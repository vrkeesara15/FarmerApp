-- AN-001 / AN-005 store daily sales. Cluster heads: own cluster; store managers: own store.
{{ authorised_view('mart_store_daily', grain='store', scoped_roles=['cluster_head', 'store_manager']) }}
