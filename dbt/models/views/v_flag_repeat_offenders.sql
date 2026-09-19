-- AN-009 repeat offenders. Cluster heads: own cluster.
{{ authorised_view('mart_flag_repeat_offenders', grain='store', scoped_roles=['cluster_head']) }}
