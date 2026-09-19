-- AN-002 field team scorecard. Cluster heads: own cluster (SPEC 5.1 audience: owner, cluster head).
{{ authorised_view('mart_officer_scorecard_30d', grain='store', scoped_roles=['cluster_head']) }}
