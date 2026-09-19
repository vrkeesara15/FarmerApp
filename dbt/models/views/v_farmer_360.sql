-- AN-004 farmer 360 (farmer_id + masked phone only, AN-014). Cluster heads: farmers of their cluster's stores.
{{ authorised_view('mart_farmer_360', grain='store', scoped_roles=['cluster_head']) }}
