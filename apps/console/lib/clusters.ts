/**
 * `GET /v1/clusters` (apps/api farmerapp/tenants/clusters_router.py): cluster names, district
 * and the store ids the caller may see (SPEC 2.6 scope). Used by the AN-011 cluster filter and
 * the C101 cluster pickers.
 */
import { authedFetch } from "./api";

export interface Cluster {
  id: string;
  name: string;
  district: string | null;
  state: string;
  store_ids: string[];
}

export interface ClusterList {
  items: Cluster[];
}

export const clustersApi = {
  list: () => authedFetch<ClusterList>("v1/clusters"),
};
