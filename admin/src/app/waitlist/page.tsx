// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Users, RefreshCw, CheckCircle, XCircle, Trash2, ChevronLeft, ChevronRight, Filter } from 'lucide-react';

const STATUS_COLORS: Record<string, string> = {
  pending:  'bg-yellow-100 text-yellow-700',
  approved: 'bg-green-100 text-green-700',
  rejected: 'bg-red-100 text-red-700',
  invited:  'bg-blue-100 text-blue-700',
};

export default function WaitlistPage() {
  const [entries, setEntries] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(0);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [notesModal, setNotesModal] = useState<{ id: string; notes: string } | null>(null);
  const limit = 50;

  const fetchList = (p = page, status = statusFilter) => {
    setLoading(true);
    api.listWaitlist({ status: status || undefined, limit, offset: p * limit })
      .then((data) => {
        setEntries(data.entries || []);
        setTotal(data.total || 0);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchList(page, statusFilter); }, [page, statusFilter]);

  const handleStatusChange = async (id: string, status: string) => {
    setActionLoading(id + status);
    try {
      await api.updateWaitlist(id, { status });
      fetchList();
    } catch (e: any) {
      alert(`Failed: ${e.message}`);
    }
    setActionLoading(null);
  };

  const handleDelete = async (id: string, email: string) => {
    if (!confirm(`Delete waitlist entry for ${email}?`)) return;
    setActionLoading(id + 'del');
    try {
      await api.deleteWaitlist(id);
      fetchList();
    } catch (e: any) {
      alert(`Failed: ${e.message}`);
    }
    setActionLoading(null);
  };

  const handleSaveNotes = async () => {
    if (!notesModal) return;
    setActionLoading('notes');
    try {
      await api.updateWaitlist(notesModal.id, { notes: notesModal.notes });
      setNotesModal(null);
      fetchList();
    } catch (e: any) {
      alert(`Failed: ${e.message}`);
    }
    setActionLoading(null);
  };

  const totalPages = Math.max(1, Math.ceil(total / limit));

  const counts: Record<string, number> = {};
  entries.forEach((e) => { counts[e.status || 'pending'] = (counts[e.status || 'pending'] || 0) + 1; });

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Users className="w-6 h-6 text-brand-500" /> Waitlist
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            {total} total {statusFilter ? `(filtered: ${statusFilter})` : ''}
          </p>
        </div>
        <button onClick={() => fetchList()} className="btn-secondary text-sm flex items-center gap-1">
          <RefreshCw className="w-4 h-4" /> Refresh
        </button>
      </div>

      {/* Filter tabs */}
      <div className="flex gap-2 mb-4">
        {['', 'pending', 'approved', 'rejected', 'invited'].map((s) => (
          <button
            key={s}
            onClick={() => { setStatusFilter(s); setPage(0); }}
            className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              statusFilter === s
                ? 'bg-brand-500 text-white'
                : 'bg-warm-100 text-gray-600 hover:bg-warm-200'
            }`}
          >
            {s === '' ? 'All' : s.charAt(0).toUpperCase() + s.slice(1)}
          </button>
        ))}
      </div>

      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-8 animate-pulse space-y-3">
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} className="h-12 bg-warm-300 rounded" />
            ))}
          </div>
        ) : entries.length === 0 ? (
          <div className="p-8 text-center text-gray-400">
            No waitlist entries{statusFilter ? ` with status "${statusFilter}"` : ''}.
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-warm-100 border-b border-warm-300">
                <tr>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Email</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Name</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Referral</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Status</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Joined</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Notes</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-warm-100">
                {entries.map((e) => (
                  <tr key={e.id} className="hover:bg-warm-50">
                    <td className="px-4 py-2.5 font-medium text-gray-900">{e.email}</td>
                    <td className="px-4 py-2.5 text-gray-600">{e.name || '—'}</td>
                    <td className="px-4 py-2.5 text-gray-500 text-xs">
                      {e.referral_code ? <span className="font-mono bg-warm-100 px-1.5 py-0.5 rounded">{e.referral_code}</span> : '—'}
                      {e.invited_by && <span className="ml-1 text-gray-400">via {e.invited_by}</span>}
                    </td>
                    <td className="px-4 py-2.5">
                      <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_COLORS[e.status || 'pending'] || 'bg-gray-100 text-gray-600'}`}>
                        {e.status || 'pending'}
                      </span>
                    </td>
                    <td className="px-4 py-2.5 text-gray-500 text-xs whitespace-nowrap">
                      {e.created_at ? formatDateTime(e.created_at) : '—'}
                    </td>
                    <td className="px-4 py-2.5 text-gray-500 text-xs max-w-[12rem] truncate" title={e.notes}>
                      <button
                        onClick={() => setNotesModal({ id: e.id, notes: e.notes || '' })}
                        className="text-brand-500 hover:underline"
                      >
                        {e.notes ? e.notes.slice(0, 30) + (e.notes.length > 30 ? '…' : '') : '+ add note'}
                      </button>
                    </td>
                    <td className="px-4 py-2.5">
                      <div className="flex items-center gap-1">
                        {e.status !== 'approved' && (
                          <button
                            onClick={() => handleStatusChange(e.id, 'approved')}
                            disabled={actionLoading === e.id + 'approved'}
                            title="Approve"
                            className="p-1.5 rounded hover:bg-green-50 text-green-600 disabled:opacity-40"
                          >
                            <CheckCircle className="w-4 h-4" />
                          </button>
                        )}
                        {e.status !== 'rejected' && (
                          <button
                            onClick={() => handleStatusChange(e.id, 'rejected')}
                            disabled={actionLoading === e.id + 'rejected'}
                            title="Reject"
                            className="p-1.5 rounded hover:bg-red-50 text-red-500 disabled:opacity-40"
                          >
                            <XCircle className="w-4 h-4" />
                          </button>
                        )}
                        <button
                          onClick={() => handleDelete(e.id, e.email)}
                          disabled={actionLoading === e.id + 'del'}
                          title="Delete"
                          className="p-1.5 rounded hover:bg-red-50 text-red-400 disabled:opacity-40"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
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
            <p className="text-xs text-gray-500">Page {page + 1} of {totalPages}</p>
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

      {/* Notes Modal */}
      {notesModal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={() => setNotesModal(null)}>
          <div className="card p-5 w-full max-w-sm mx-4" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-sm font-semibold text-gray-800 mb-3">Admin Notes</h3>
            <textarea
              className="input w-full mb-3"
              rows={4}
              placeholder="Add notes about this applicant..."
              value={notesModal.notes}
              onChange={(e) => setNotesModal({ ...notesModal, notes: e.target.value })}
              autoFocus
            />
            <div className="flex gap-2 justify-end">
              <button onClick={() => setNotesModal(null)} className="btn-secondary text-sm">Cancel</button>
              <button onClick={handleSaveNotes} disabled={actionLoading === 'notes'} className="btn-primary text-sm">
                {actionLoading === 'notes' ? 'Saving…' : 'Save Notes'}
              </button>
            </div>
          </div>
        </div>
      )}
    </AdminShell>
  );
}
