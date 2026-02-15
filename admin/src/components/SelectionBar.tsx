'use client';

import { X } from 'lucide-react';

interface BulkAction {
  label: string;
  action: string;
  color?: string;
  icon?: React.ReactNode;
  confirm?: boolean;
}

interface SelectionBarProps {
  count: number;
  total: number;
  onSelectAll: () => void;
  onClearSelection: () => void;
  actions: BulkAction[];
  onAction: (action: string) => void;
  loading?: boolean;
}

export default function SelectionBar({ count, total, onSelectAll, onClearSelection, actions, onAction, loading }: SelectionBarProps) {
  if (count === 0) return null;

  return (
    <div className="bg-brand-50 border border-brand-200 rounded-lg px-4 py-3 mb-4 flex items-center gap-3 animate-in slide-in-from-top-2">
      <span className="text-sm font-medium text-brand-700">
        {count} selected
      </span>
      {count < total && (
        <button onClick={onSelectAll} className="text-xs text-brand-600 hover:text-brand-800 underline">
          Select all {total}
        </button>
      )}
      <div className="flex-1" />
      <div className="flex items-center gap-2">
        {actions.map((a) => (
          <button
            key={a.action}
            onClick={() => {
              if (a.confirm && !confirm(`Are you sure you want to ${a.label.toLowerCase()} ${count} items?`)) return;
              onAction(a.action);
            }}
            disabled={loading}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
              a.color || 'bg-white text-gray-700 hover:bg-gray-100 border border-gray-200'
            }`}
          >
            {a.icon}
            {a.label}
          </button>
        ))}
        <button onClick={onClearSelection} className="p-1.5 rounded hover:bg-brand-100 text-brand-500" title="Clear selection">
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}
