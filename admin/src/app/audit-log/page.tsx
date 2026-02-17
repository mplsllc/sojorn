'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { ScrollText, RefreshCw, ChevronLeft, ChevronRight } from 'lucide-react';

const ACTION_COLORS: Record<string, string> = {
  ban: 'bg-red-100 text-red-700',
  suspend: 'bg-orange-100 text-orange-700',
  activate: 'bg-green-100 text-green-700',
  delete: 'bg-red-100 text-red-700',
  admin_create_user: 'bg-blue-100 text-blue-700',
  admin_import_content: 'bg-blue-100 text-blue-700',
  waitlist_update: 'bg-purple-100 text-purple-700',
  reset_feed_impressions: 'bg-yellow-100 text-yellow-700',
};

function actionColor(action: string) {
  return ACTION_COLORS[action] || 'bg-gray-100 text-gray-600';
}

export default function AuditLogPage() {
  const [entries, setEntries] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(0);
  const limit = 50;

  const fetchLog = (p = page) => {
    setLoading(true);
    api.getAuditLog({ limit, offset: p * limit })
      .then((data) => {
        setEntries(data.entries || []);
        setTotal(data.total || 0);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchLog(page); }, [page]);

  const totalPages = Math.max(1, Math.ceil(total / limit));

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <ScrollText className="w-6 h-6 text-brand-500" /> Admin Audit Log
          </h1>
          <p className="text-sm text-gray-500 mt-1">Every admin action is recorded here</p>
        </div>
        <button onClick={() => fetchLog(page)} className="btn-secondary text-sm flex items-center gap-1">
          <RefreshCw className="w-4 h-4" /> Refresh
        </button>
      </div>

      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-8 animate-pulse space-y-3">
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} className="h-10 bg-warm-300 rounded" />
            ))}
          </div>
        ) : entries.length === 0 ? (
          <div className="p-8 text-center text-gray-400">No audit log entries found.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-warm-100 border-b border-warm-300">
                <tr>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">When</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Admin</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Action</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Target</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Details</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-warm-100">
                {entries.map((e) => (
                  <tr key={e.id} className="hover:bg-warm-50">
                    <td className="px-4 py-2.5 text-gray-500 text-xs whitespace-nowrap">
                      {e.created_at ? formatDateTime(e.created_at) : '—'}
                    </td>
                    <td className="px-4 py-2.5 text-gray-700 font-medium">
                      {e.actor_handle ? `@${e.actor_handle}` : e.actor_id ? e.actor_id.slice(0, 8) + '…' : '—'}
                    </td>
                    <td className="px-4 py-2.5">
                      <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${actionColor(e.action)}`}>
                        {e.action?.replace(/_/g, ' ')}
                      </span>
                    </td>
                    <td className="px-4 py-2.5 text-gray-500 text-xs">
                      {e.target_type && <span className="font-medium text-gray-700">{e.target_type}</span>}
                      {e.target_id && <span className="ml-1 font-mono">{String(e.target_id).slice(0, 8)}…</span>}
                    </td>
                    <td className="px-4 py-2.5 text-gray-500 text-xs max-w-xs truncate" title={e.details}>
                      {e.details || '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="flex items-center justify-between px-4 py-3 border-t border-warm-200">
            <p className="text-xs text-gray-500">
              Page {page + 1} of {totalPages} ({total} entries)
            </p>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                disabled={page === 0}
                className="p-1.5 rounded border border-warm-300 disabled:opacity-40 hover:bg-warm-100"
              >
                <ChevronLeft className="w-4 h-4" />
              </button>
              <button
                onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
                disabled={page >= totalPages - 1}
                className="p-1.5 rounded border border-warm-300 disabled:opacity-40 hover:bg-warm-100"
              >
                <ChevronRight className="w-4 h-4" />
              </button>
            </div>
          </div>
        )}
      </div>
    </AdminShell>
  );
}
