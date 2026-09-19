-- AN-002 officer daily trend. Cluster heads: own cluster.
{{ authorised_view('mart_officer_daily', grain='store', scoped_roles=['cluster_head']) }}
