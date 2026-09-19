-- AN-005 credit book per farmer x store (farmer_id only). Store managers: own store; cluster heads: own cluster.
{{ authorised_view('mart_credit_accounts', grain='store', scoped_roles=['cluster_head', 'store_manager']) }}
