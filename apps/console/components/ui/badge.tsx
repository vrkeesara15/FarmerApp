import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const badgeVariants = cva(
  "inline-flex items-center gap-1 rounded-pill border px-2 py-0.5 text-small font-semibold leading-[18px] whitespace-nowrap",
  {
    variants: {
      variant: {
        default: "border-transparent bg-primary-container text-primary",
        secondary: "border-transparent bg-secondary-container text-secondary-on",
        success: "border-transparent bg-success-container text-success",
        warning: "border-transparent bg-warning-container text-warning",
        danger: "border-transparent bg-danger-container text-danger",
        info: "border-transparent bg-info-container text-info",
        outline: "border-border bg-transparent text-text",
        neutral: "border-transparent bg-background text-text-secondary",
      },
    },
    defaultVariants: { variant: "default" },
  },
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}

export { Badge, badgeVariants };
