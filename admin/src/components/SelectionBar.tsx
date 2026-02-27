// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import { useState } from 'react';
import { X, AlertTriangle } from 'lucide-react';

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
  const [pendingAction, setPendingAction] = useState<BulkAction | null>(null);

  if (count === 0) return null;

  const handleAction = (a: BulkAction) => {
    if (a.confirm) {
      setPendingAction(a);
    } else {
      onAction(a.action);
    }
  };

  const confirmAction = () => {
    if (pendingAction) {
      onAction(pendingAction.action);
      setPendingAction(null);
    }
  };

  return (
    <>
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
              onClick={() => handleAction(a)}
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

      {/* Confirmation Modal */}
      {pendingAction && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={() => setPendingAction(null)}>
          <div className="bg-white rounded-xl shadow-xl p-6 max-w-md w-full mx-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-red-100 flex items-center justify-center flex-shrink-0">
                <AlertTriangle className="w-5 h-5 text-red-600" />
              </div>
              <div>
                <h3 className="text-lg font-semibold text-gray-900">Confirm Bulk Action</h3>
                <p className="text-sm text-gray-500">This action cannot be undone.</p>
              </div>
            </div>
            <p className="text-sm text-gray-700 mb-6">
              This will <strong>{pendingAction.label.toLowerCase()}</strong> {count} {count === 1 ? 'item' : 'items'}.
              Are you sure you want to proceed?
            </p>
            <div className="flex justify-end gap-3">
              <button
                onClick={() => setPendingAction(null)}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={confirmAction}
                className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-lg hover:bg-red-700 transition-colors"
              >
                {pendingAction.label} {count} {count === 1 ? 'item' : 'items'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
