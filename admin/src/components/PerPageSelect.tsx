// Copyright (c) 2026 MPLS LLC — AGPL-3.0

export const PER_PAGE_OPTIONS = [10, 25, 50, 100] as const;
export type PerPage = (typeof PER_PAGE_OPTIONS)[number];

interface Props {
  value: number;
  onChange: (n: number) => void;
}

export default function PerPageSelect({ value, onChange }: Props) {
  return (
    <div className="flex items-center gap-1.5">
      <span className="text-xs text-gray-500 whitespace-nowrap">Per page</span>
      <select
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="text-xs border border-warm-300 rounded px-1.5 py-1 bg-white focus:outline-none focus:ring-1 focus:ring-brand-500"
      >
        {PER_PAGE_OPTIONS.map((n) => (
          <option key={n} value={n}>{n}</option>
        ))}
      </select>
    </div>
  );
}
