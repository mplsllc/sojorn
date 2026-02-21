// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import { AtSign, Plus, Trash2, Search, Check, X, Clock, ChevronDown, Upload } from 'lucide-react';

const CATEGORIES = [
  { value: '', label: 'All Categories' },
  { value: 'platform', label: 'Platform' },
  { value: 'brand', label: 'Brand' },
  { value: 'public_figure', label: 'Public Figure' },
  { value: 'custom', label: 'Custom' },
];

export default function UsernamesPage() {
  const [tab, setTab] = useState<'reserved' | 'claims'>('reserved');

  return (
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Username Management</h1>
        <p className="text-sm text-gray-500 mt-1">Manage reserved usernames and review claim requests</p>
      </div>

      {/* Tab Switcher */}
      <div className="flex gap-1 bg-warm-200 p-1 rounded-lg w-fit mb-6">
        <button
          onClick={() => setTab('reserved')}
          className={`px-4 py-2 text-sm font-medium rounded-md transition-colors ${
            tab === 'reserved' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          Reserved Usernames
        </button>
        <button
          onClick={() => setTab('claims')}
          className={`px-4 py-2 text-sm font-medium rounded-md transition-colors ${
            tab === 'claims' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          Claim Requests
        </button>
      </div>

      {tab === 'reserved' ? <ReservedTab /> : <ClaimsTab />}
    </AdminShell>
  );
}

// ─── Reserved Usernames Tab ───────────────────────────────

function ReservedTab() {
  const [items, setItems] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('');
  const [showAdd, setShowAdd] = useState(false);
  const [showBulk, setShowBulk] = useState(false);
  const [addForm, setAddForm] = useState({ username: '', category: 'custom', reason: '' });
  const [bulkForm, setBulkForm] = useState({ text: '', category: 'custom', reason: '' });
  const [saving, setSaving] = useState(false);
  const [offset, setOffset] = useState(0);
  const limit = 50;

  const load = () => {
    setLoading(true);
    api.listReservedUsernames({ search: search || undefined, category: category || undefined, limit, offset })
      .then((data) => {
        setItems(data.reserved_usernames || []);
        setTotal(data.total || 0);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, [search, category, offset]);

  const handleAdd = async () => {
    if (!addForm.username.trim()) return;
    setSaving(true);
    try {
      await api.addReservedUsername(addForm);
      setAddForm({ username: '', category: 'custom', reason: '' });
      setShowAdd(false);
      load();
    } catch (e: any) {
      alert(e.message);
    } finally {
      setSaving(false);
    }
  };

  const handleBulkAdd = async () => {
    const usernames = bulkForm.text.split('\n').map(u => u.trim()).filter(Boolean);
    if (usernames.length === 0) return;
    setSaving(true);
    try {
      const res = await api.bulkAddReservedUsernames({ usernames, category: bulkForm.category, reason: bulkForm.reason });
      alert(res.message);
      setBulkForm({ text: '', category: 'custom', reason: '' });
      setShowBulk(false);
      load();
    } catch (e: any) {
      alert(e.message);
    } finally {
      setSaving(false);
    }
  };

  const handleRemove = async (id: string, username: string) => {
    if (!confirm(`Remove "${username}" from reserved list?`)) return;
    try {
      await api.removeReservedUsername(id);
      load();
    } catch (e: any) {
      alert(e.message);
    }
  };

  return (
    <div>
      {/* Actions Bar */}
      <div className="flex items-center gap-3 mb-4">
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search usernames..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setOffset(0); }}
            className="w-full pl-9 pr-3 py-2 text-sm border border-warm-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
        </div>
        <select
          value={category}
          onChange={(e) => { setCategory(e.target.value); setOffset(0); }}
          className="text-sm border border-warm-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
        >
          {CATEGORIES.map((c) => (
            <option key={c.value} value={c.value}>{c.label}</option>
          ))}
        </select>
        <button onClick={() => setShowAdd(!showAdd)} className="btn-primary text-sm flex items-center gap-1.5">
          <Plus className="w-4 h-4" /> Add
        </button>
        <button onClick={() => setShowBulk(!showBulk)} className="btn-secondary text-sm flex items-center gap-1.5">
          <Upload className="w-4 h-4" /> Bulk Add
        </button>
      </div>

      {/* Add Form */}
      {showAdd && (
        <div className="card p-4 mb-4">
          <h3 className="text-sm font-semibold text-gray-700 mb-3">Add Reserved Username</h3>
          <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
            <input
              type="text"
              placeholder="Username"
              value={addForm.username}
              onChange={(e) => setAddForm({ ...addForm, username: e.target.value.toLowerCase() })}
              className="text-sm border border-warm-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
            <select
              value={addForm.category}
              onChange={(e) => setAddForm({ ...addForm, category: e.target.value })}
              className="text-sm border border-warm-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              <option value="platform">Platform</option>
              <option value="brand">Brand</option>
              <option value="public_figure">Public Figure</option>
              <option value="custom">Custom</option>
            </select>
            <input
              type="text"
              placeholder="Reason (optional)"
              value={addForm.reason}
              onChange={(e) => setAddForm({ ...addForm, reason: e.target.value })}
              className="text-sm border border-warm-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
            <button onClick={handleAdd} disabled={saving} className="btn-primary text-sm">
              {saving ? 'Saving...' : 'Reserve'}
            </button>
          </div>
        </div>
      )}

      {/* Bulk Add Form */}
      {showBulk && (
        <div className="card p-4 mb-4">
          <h3 className="text-sm font-semibold text-gray-700 mb-3">Bulk Add Reserved Usernames</h3>
          <p className="text-xs text-gray-400 mb-2">One username per line</p>
          <textarea
            rows={6}
            placeholder={"google\napple\nmicrosoft\n..."}
            value={bulkForm.text}
            onChange={(e) => setBulkForm({ ...bulkForm, text: e.target.value })}
            className="w-full text-sm border border-warm-300 rounded-lg px-3 py-2 mb-3 focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono"
          />
          <div className="flex items-center gap-3">
            <select
              value={bulkForm.category}
              onChange={(e) => setBulkForm({ ...bulkForm, category: e.target.value })}
              className="text-sm border border-warm-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              <option value="platform">Platform</option>
              <option value="brand">Brand</option>
              <option value="public_figure">Public Figure</option>
              <option value="custom">Custom</option>
            </select>
            <input
              type="text"
              placeholder="Reason (optional)"
              value={bulkForm.reason}
              onChange={(e) => setBulkForm({ ...bulkForm, reason: e.target.value })}
              className="text-sm border border-warm-300 rounded-lg px-3 py-2 flex-1 focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
            <button onClick={handleBulkAdd} disabled={saving} className="btn-primary text-sm">
              {saving ? 'Adding...' : `Add ${bulkForm.text.split('\n').filter(Boolean).length} Usernames`}
            </button>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="card overflow-hidden">
        <div className="px-4 py-3 border-b border-warm-200 flex items-center justify-between">
          <span className="text-sm font-medium text-gray-700">{total} reserved username{total !== 1 ? 's' : ''}</span>
        </div>
        {loading ? (
          <div className="p-8 text-center text-gray-400 text-sm">Loading...</div>
        ) : items.length === 0 ? (
          <div className="p-8 text-center text-gray-400 text-sm">No reserved usernames found</div>
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-warm-200 bg-warm-100">
                <th className="text-left px-4 py-2.5 font-medium text-gray-600">Username</th>
                <th className="text-left px-4 py-2.5 font-medium text-gray-600">Category</th>
                <th className="text-left px-4 py-2.5 font-medium text-gray-600">Reason</th>
                <th className="text-left px-4 py-2.5 font-medium text-gray-600">Added</th>
                <th className="text-right px-4 py-2.5 font-medium text-gray-600">Actions</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item) => (
                <tr key={item.id} className="border-b border-warm-100 hover:bg-warm-50 transition-colors">
                  <td className="px-4 py-2.5 font-mono font-medium text-gray-900">@{item.username}</td>
                  <td className="px-4 py-2.5">
                    <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
                      item.category === 'platform' ? 'bg-blue-100 text-blue-700' :
                      item.category === 'brand' ? 'bg-purple-100 text-purple-700' :
                      item.category === 'public_figure' ? 'bg-amber-100 text-amber-700' :
                      'bg-gray-100 text-gray-700'
                    }`}>
                      {item.category.replace('_', ' ')}
                    </span>
                  </td>
                  <td className="px-4 py-2.5 text-gray-500 max-w-xs truncate">{item.reason || '—'}</td>
                  <td className="px-4 py-2.5 text-gray-400">{new Date(item.created_at).toLocaleDateString()}</td>
                  <td className="px-4 py-2.5 text-right">
                    <button
                      onClick={() => handleRemove(item.id, item.username)}
                      className="p-1.5 text-red-500 hover:bg-red-50 rounded-lg transition-colors"
                      title="Remove"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {/* Pagination */}
        {total > limit && (
          <div className="px-4 py-3 border-t border-warm-200 flex items-center justify-between">
            <span className="text-xs text-gray-400">
              Showing {offset + 1}–{Math.min(offset + limit, total)} of {total}
            </span>
            <div className="flex gap-2">
              <button
                onClick={() => setOffset(Math.max(0, offset - limit))}
                disabled={offset === 0}
                className="text-xs px-3 py-1.5 border border-warm-300 rounded-lg disabled:opacity-40"
              >
                Previous
              </button>
              <button
                onClick={() => setOffset(offset + limit)}
                disabled={offset + limit >= total}
                className="text-xs px-3 py-1.5 border border-warm-300 rounded-lg disabled:opacity-40"
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Claim Requests Tab ───────────────────────────────────

function ClaimsTab() {
  const [items, setItems] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState('pending');
  const [reviewingId, setReviewingId] = useState<string | null>(null);
  const [reviewNotes, setReviewNotes] = useState('');
  const [saving, setSaving] = useState(false);

  const load = () => {
    setLoading(true);
    api.listClaimRequests({ status })
      .then((data) => {
        setItems(data.claim_requests || []);
        setTotal(data.total || 0);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { load(); }, [status]);

  const handleReview = async (id: string, decision: 'approved' | 'denied') => {
    setSaving(true);
    try {
      await api.reviewClaimRequest(id, decision, reviewNotes);
      setReviewingId(null);
      setReviewNotes('');
      load();
    } catch (e: any) {
      alert(e.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      {/* Status Filter */}
      <div className="flex gap-2 mb-4">
        {['pending', 'approved', 'denied'].map((s) => (
          <button
            key={s}
            onClick={() => setStatus(s)}
            className={`px-3 py-1.5 text-sm rounded-lg font-medium transition-colors ${
              status === s
                ? s === 'pending' ? 'bg-yellow-100 text-yellow-800' :
                  s === 'approved' ? 'bg-green-100 text-green-800' :
                  'bg-red-100 text-red-800'
                : 'bg-warm-200 text-gray-600 hover:bg-warm-300'
            }`}
          >
            {s.charAt(0).toUpperCase() + s.slice(1)}
          </button>
        ))}
      </div>

      {/* Cards */}
      {loading ? (
        <div className="card p-8 text-center text-gray-400 text-sm">Loading...</div>
      ) : items.length === 0 ? (
        <div className="card p-8 text-center text-gray-400 text-sm">No {status} claim requests</div>
      ) : (
        <div className="space-y-3">
          {items.map((item) => (
            <div key={item.id} className="card p-4">
              <div className="flex items-start justify-between gap-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-mono font-bold text-gray-900">@{item.requested_username}</span>
                    <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
                      item.status === 'pending' ? 'bg-yellow-100 text-yellow-700' :
                      item.status === 'approved' ? 'bg-green-100 text-green-700' :
                      'bg-red-100 text-red-700'
                    }`}>
                      {item.status}
                    </span>
                  </div>

                  <div className="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-1 text-sm mt-2">
                    <div><span className="text-gray-400">Email:</span> <span className="text-gray-700">{item.requester_email}</span></div>
                    {item.requester_name && <div><span className="text-gray-400">Name:</span> <span className="text-gray-700">{item.requester_name}</span></div>}
                    {item.organization && <div><span className="text-gray-400">Organization:</span> <span className="text-gray-700">{item.organization}</span></div>}
                    {item.proof_url && <div><span className="text-gray-400">Proof:</span> <a href={item.proof_url} target="_blank" rel="noopener" className="text-brand-600 hover:underline">{item.proof_url}</a></div>}
                    <div><span className="text-gray-400">Submitted:</span> <span className="text-gray-700">{new Date(item.created_at).toLocaleString()}</span></div>
                  </div>

                  <div className="mt-2 p-2 bg-warm-100 rounded-lg text-sm text-gray-600">
                    <span className="font-medium text-gray-500">Justification:</span> {item.justification}
                  </div>

                  {item.review_notes && (
                    <div className="mt-2 p-2 bg-blue-50 rounded-lg text-sm text-blue-700">
                      <span className="font-medium">Review notes:</span> {item.review_notes}
                    </div>
                  )}
                </div>

                {/* Actions */}
                {item.status === 'pending' && (
                  <div className="flex flex-col gap-2 flex-shrink-0">
                    {reviewingId === item.id ? (
                      <div className="w-64">
                        <textarea
                          rows={2}
                          placeholder="Review notes (optional)..."
                          value={reviewNotes}
                          onChange={(e) => setReviewNotes(e.target.value)}
                          className="w-full text-sm border border-warm-300 rounded-lg px-3 py-2 mb-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
                        />
                        <div className="flex gap-2">
                          <button
                            onClick={() => handleReview(item.id, 'approved')}
                            disabled={saving}
                            className="flex-1 flex items-center justify-center gap-1 px-3 py-1.5 text-sm font-medium bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors disabled:opacity-50"
                          >
                            <Check className="w-3.5 h-3.5" /> Approve
                          </button>
                          <button
                            onClick={() => handleReview(item.id, 'denied')}
                            disabled={saving}
                            className="flex-1 flex items-center justify-center gap-1 px-3 py-1.5 text-sm font-medium bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors disabled:opacity-50"
                          >
                            <X className="w-3.5 h-3.5" /> Deny
                          </button>
                        </div>
                        <button
                          onClick={() => { setReviewingId(null); setReviewNotes(''); }}
                          className="w-full mt-1 text-xs text-gray-400 hover:text-gray-600"
                        >
                          Cancel
                        </button>
                      </div>
                    ) : (
                      <button
                        onClick={() => setReviewingId(item.id)}
                        className="btn-primary text-sm"
                      >
                        Review
                      </button>
                    )}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
