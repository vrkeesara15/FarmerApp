"use client";

import * as React from "react";
import { Tabs as TabsRoot, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";

export interface TabItem<V extends string = string> {
  value: V;
  label: string;
  /** Count badge shown after the label. */
  count?: number;
  disabled?: boolean;
  content?: React.ReactNode;
}

export interface TabsProps<V extends string = string> {
  items: ReadonlyArray<TabItem<V>>;
  value?: V;
  defaultValue?: V;
  onValueChange?: (value: V) => void;
  /** Accessible name for the tab list. */
  label: string;
  className?: string;
}

export function Tabs<V extends string = string>({
  items,
  value,
  defaultValue,
  onValueChange,
  label,
  className,
}: TabsProps<V>) {
  return (
    <TabsRoot
      value={value}
      defaultValue={defaultValue ?? items[0]?.value}
      onValueChange={(v) => onValueChange?.(v as V)}
      className={cn("w-full", className)}
    >
      <TabsList aria-label={label}>
        {items.map((item) => (
          <TabsTrigger key={item.value} value={item.value} disabled={item.disabled}>
            {item.label}
            {item.count !== undefined ? (
              <span className="tnum ml-1.5 rounded-pill bg-background px-1.5 text-small text-text-secondary">
                {item.count}
              </span>
            ) : null}
          </TabsTrigger>
        ))}
      </TabsList>
      {items.map((item) =>
        item.content !== undefined ? (
          <TabsContent key={item.value} value={item.value}>
            {item.content}
          </TabsContent>
        ) : null,
      )}
    </TabsRoot>
  );
}
