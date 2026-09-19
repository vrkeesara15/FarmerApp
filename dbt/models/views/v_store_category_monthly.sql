-- AN-005 sales by category and brand with margin. Store managers: own store; cluster heads: own cluster.
{{ authorised_view('mart_store_category_monthly', grain='store', scoped_roles=['cluster_head', 'store_manager']) }}
