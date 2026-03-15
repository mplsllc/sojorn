// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import PerPageSelect from '@/components/PerPageSelect';
import { api } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { ScrollText, RefreshCw, ChevronLeft, ChevronRight, Download, Trash2, Filter, X, Info, AlertTriangle, Search } from 'lucide-react';

const ACTION_TYPES = [
  'ban', 'suspend', 'activate', 'delete', 'warn',
  'admin_create_user', 'admin_import_content',
  'waitlist_update', 'reset_feed_impressions',
  'ai_moderation_feedback', 'admin_upsert_official_account',
  'admin_delete_official_account', 'admin_toggle_official_account',
  'update_role', 'update_verification', 'update_status',
  'update_email_template', 'update_post_thumbnail',
];

const ACTION_COLORS: Record<string, string> = {
  ban: 'bg-red-100 text-red-700',
  suspend: 'bg-orange-100 text-orange-700',
  activate: 'bg-green-100 text-green-700',
  delete: 'bg-red-100 text-red-700',
  warn: 'bg-yellow-100 text-yellow-700',
  admin_create_user: 'bg-blue-100 text-blue-700',
  admin_import_content: 'bg-blue-100 text-blue-700',
  waitlist_update: 'bg-purple-100 text-purple-700',
  reset_feed_impressions: 'bg-yellow-100 text-yellow-700',
  ai_moderation_feedback: 'bg-indigo-100 text-indigo-700',
};

function actionColor(action: string) {
  return ACTION_COLORS[action] || 'bg-gray-100 text-gray-600';
}

export default function AuditLogPage() {
  const [entries, setEntries] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(0);
  const [limit, setLimit] = useState(50);

  // Filters
  const [actionFilter, setActionFilter] = useState('');
  const [searchFilter, setSearchFilter] = useState('');
  const [fromDate, setFromDate] = useState('');
  const [toDate, setToDate] = useState('');
  const [filtersOpen, setFiltersOpen] = useState(false);

  // Purge
  const [purgeModal, setPurgeModal] = useState(false);
  const [purgeDays, setPurgeDays] = useState(90);
  const [purging, setPurging] = useState(false);

  // Export
  const [exporting, setExporting] = useState(false);

  const hasFilters = actionFilter || searchFilter || fromDate || toDate;

  // Stable ref for current filter values — avoids useCallback/useEffect dependency loops
  const [trigger, setTrigger] = useState(0);

  const fetchLog = (p: number) => {
    setLoading(true);
    api.getAuditLog({
      limit,
      offset: p * limit,
      action: actionFilter || undefined,
      search: searchFilter || undefined,
      from: fromDate || undefined,
      to: toDate || undefined,
    })
      .then((data) => {
        setEntries(data.entries || []);
        setTotal(data.total || 0);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchLog(page); }, [page, trigger]); // eslint-disable-line react-hooks/exhaustive-deps

  const applyFilters = () => {
    setPage(0);
    setTrigger((t) => t + 1);
  };

  const clearFilters = () => {
    setActionFilter('');
    setSearchFilter('');
    setFromDate('');
    setToDate('');
    setPage(0);
    setTrigger((t) => t + 1);
  };

  const handleExport = async () => {
    setExporting(true);
    try {
      const data = await api.getAuditLog({
        limit: 10000,
        offset: 0,
        action: actionFilter || undefined,
        search: searchFilter || undefined,
        from: fromDate || undefined,
        to: toDate || undefined,
      });
      const rows = data.entries || [];
      if (rows.length === 0) return;

      const header = 'Timestamp,Admin,Action,Target Type,Target ID,Details';
      const csvRows = rows.map((e: any) => {
        const ts = e.created_at ? new Date(e.created_at).toISOString() : '';
        const admin = e.actor_handle ? `@${e.actor_handle}` : e.actor_id || '';
        const details = (e.details || '').replace(/"/g, '""');
        return `"${ts}","${admin}","${e.action}","${e.target_type}","${e.target_id || ''}","${details}"`;
      });

      const csv = header + '\n' + csvRows.join('\n');
      const blob = new Blob([csv], { type: 'text/csv' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `audit-log-${new Date().toISOString().slice(0, 10)}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {}
    setExporting(false);
  };

  const handlePurge = async () => {
    setPurging(true);
    try {
      const result = await api.purgeAuditLog(purgeDays);
      setPurgeModal(false);
      fetchLog(page);
      alert(`Purged ${result.deleted} entries older than ${purgeDays} days.`);
    } catch {
      alert('Failed to purge audit log.');
    }
    setPurging(false);
  };

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
        <div className="flex items-center gap-2">
          <button onClick={handleExport} disabled={exporting || total === 0} className="btn-secondary text-sm flex items-center gap-1 disabled:opacity-50">
            <Download className="w-4 h-4" /> {exporting ? 'Exporting...' : 'Export CSV'}
          </button>
          <button onClick={() => fetchLog(page)} className="btn-secondary text-sm flex items-center gap-1">
            <RefreshCw className="w-4 h-4" /> Refresh
          </button>
        </div>
      </div>

      {/* Retention Info Banner */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg px-4 py-3 mb-4 flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm text-blue-700">
          <Info className="w-4 h-4 flex-shrink-0" />
          <span>Entries older than 90 days are automatically purged daily at 3 AM UTC.</span>
        </div>
        <button onClick={() => setPurgeModal(true)} className="text-xs text-red-600 hover:text-red-800 font-medium flex items-center gap-1">
          <Trash2 className="w-3.5 h-3.5" /> Purge now
        </button>
      </div>

      {/* Filter Bar */}
      <div className="mb-4">
        <button
          onClick={() => setFiltersOpen(!filtersOpen)}
          className={`flex items-center gap-2 text-sm font-medium px-3 py-2 rounded-lg transition-colors ${
            hasFilters ? 'bg-brand-50 text-brand-700 border border-brand-200' : 'text-gray-600 hover:bg-warm-100'
          }`}
        >
          <Filter className="w-4 h-4" />
          Filters
          {hasFilters && (
            <span className="bg-brand-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center">
              {[actionFilter, searchFilter, fromDate, toDate].filter(Boolean).length}
            </span>
          )}
        </button>

        {filtersOpen && (
          <div className="mt-3 bg-white border border-warm-200 rounded-lg p-4 flex flex-wrap items-end gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Action Type</label>
              <select
                value={actionFilter}
                onChange={(e) => setActionFilter(e.target.value)}
                className="px-3 py-2 border border-warm-300 rounded-lg text-sm bg-white min-w-[180px]"
              >
                <option value="">All actions</option>
                {ACTION_TYPES.map((a) => (
                  <option key={a} value={a}>{a.replace(/_/g, ' ')}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Search Details</label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                <input
                  type="text"
                  value={searchFilter}
                  onChange={(e) => setSearchFilter(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && applyFilters()}
                  placeholder="Search details..."
                  className="pl-9 pr-3 py-2 border border-warm-300 rounded-lg text-sm w-[200px]"
                />
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">From</label>
              <input
                type="date"
                value={fromDate}
                onChange={(e) => setFromDate(e.target.value)}
                className="px-3 py-2 border border-warm-300 rounded-lg text-sm"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">To</label>
              <input
                type="date"
                value={toDate}
                onChange={(e) => setToDate(e.target.value)}
                className="px-3 py-2 border border-warm-300 rounded-lg text-sm"
              />
            </div>
            <button onClick={applyFilters} className="btn-primary text-sm px-4 py-2">
              Apply
            </button>
            {hasFilters && (
              <button onClick={clearFilters} className="text-sm text-gray-500 hover:text-gray-700 flex items-center gap-1">
                <X className="w-4 h-4" /> Clear
              </button>
            )}
          </div>
        )}
      </div>

      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-8 animate-pulse space-y-3">
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} className="h-10 bg-warm-300 rounded" />
            ))}
          </div>
        ) : entries.length === 0 ? (
          <div className="p-8 text-center text-gray-400">
            {hasFilters ? 'No entries match your filters.' : 'No audit log entries found.'}
          </div>
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
        <div className="flex items-center justify-between px-4 py-3 border-t border-warm-200">
          <p className="text-xs text-gray-500">
            Page {page + 1} of {totalPages} ({total.toLocaleString()} entries)
          </p>
          <div className="flex items-center gap-3">
            <PerPageSelect value={limit} onChange={(n) => { setLimit(n); setPage(0); setTrigger((t) => t + 1); }} />
            <button
              type="button"
              onClick={() => setPage((p) => Math.max(0, p - 1))}
              disabled={page === 0}
              title="Previous page"
              className="p-1.5 rounded border border-warm-300 disabled:opacity-40 hover:bg-warm-100"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <button
              type="button"
              onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
              disabled={page >= totalPages - 1}
              title="Next page"
              className="p-1.5 rounded border border-warm-300 disabled:opacity-40 hover:bg-warm-100"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Purge Confirmation Modal */}
      {purgeModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={() => setPurgeModal(false)}>
          <div className="bg-white rounded-xl shadow-xl p-6 max-w-md w-full mx-4" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-red-100 flex items-center justify-center flex-shrink-0">
                <AlertTriangle className="w-5 h-5 text-red-600" />
              </div>
              <div>
                <h3 className="text-lg font-semibold text-gray-900">Purge Audit Log</h3>
                <p className="text-sm text-gray-500">This permanently deletes old entries.</p>
              </div>
            </div>
            <div className="mb-6">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Delete entries older than:
              </label>
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  value={purgeDays}
                  onChange={(e) => setPurgeDays(Math.max(30, parseInt(e.target.value) || 30))}
                  min={30}
                  className="w-24 px-3 py-2 border border-warm-300 rounded-lg text-sm"
                />
                <span className="text-sm text-gray-600">days (minimum 30)</span>
              </div>
            </div>
            <div className="flex justify-end gap-3">
              <button
                onClick={() => setPurgeModal(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handlePurge}
                disabled={purging}
                className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-lg hover:bg-red-700 transition-colors disabled:opacity-50"
              >
                {purging ? 'Purging...' : `Purge entries older than ${purgeDays}d`}
              </button>
            </div>
          </div>
        </div>
      )}
    </AdminShell>
  );
}
