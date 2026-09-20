"use client";

/** Lazy map entry points (Leaflet needs `window`; kept out of the page bundle and SSR). */
import dynamic from "next/dynamic";
import { Skeleton } from "@/components/ds/Skeleton";

const MapSkeleton = () => <Skeleton className="h-80 w-full" data-testid="map-skeleton" />;

export const StoreMap = dynamic(() => import("./StoreMap"), {
  ssr: false,
  loading: MapSkeleton,
});
export const ReplayMap = dynamic(() => import("./ReplayMap"), {
  ssr: false,
  loading: MapSkeleton,
});
export const FarmsMap = dynamic(() => import("./FarmsMap"), {
  ssr: false,
  loading: MapSkeleton,
});
export const CropHealthMap = dynamic(() => import("./CropHealthMap"), {
  ssr: false,
  loading: MapSkeleton,
});
