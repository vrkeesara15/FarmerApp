import { Badge } from "@/components/ui/badge";
import { Star } from "lucide-react";
import { t } from "@/lib/i18n";
import { cn } from "@/lib/utils";

export interface OwnBrandBadgeProps {
  /** Tenant brand name; defaults to the generic "Own brand" label. */
  brandName?: string;
  compact?: boolean;
  className?: string;
}

export function OwnBrandBadge({ brandName, compact, className }: OwnBrandBadgeProps) {
  const label = brandName ?? t("ownBrand.label");
  return (
    <Badge
      variant="secondary"
      className={cn(className)}
      title={compact ? label : undefined}
      data-testid="own-brand"
    >
      <Star className="size-3.5 fill-current" aria-hidden="true" />
      {compact ? <span className="sr-only">{label}</span> : label}
    </Badge>
  );
}
