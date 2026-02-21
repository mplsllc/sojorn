// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import { useState, useEffect } from 'react';
import { api } from '@/lib/api';
import AdminShell from '@/components/AdminShell';
import { Shield, ShieldCheck, ShieldX, Plus, Trash2, Search, Globe, AlertCircle, RefreshCw, ExternalLink } from 'lucide-react';

interface SafeDomain {
  id: string;
  domain: string;
  category: string;
  is_approved: boolean;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

const CATEGORIES = ['general', 'news', 'social', 'tech', 'education', 'government', 'internal'];

export default function SafeLinksPage() {
  const [domains, setDomains] = useState<SafeDomain[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [showAdd, setShowAdd] = useState(false);
  const [checkUrl, setCheckUrl] = useState('');
  const [checkResult, setCheckResult] = useState<any>(null);
  const [checking, setChecking] = useState(false);

  const fetchDomains = async () => {
    setLoading(true);
    try {
      const data = await api.listSafeDomains(categoryFilter || undefined);
      setDomains(data.domains || []);
    } catch { }
    setLoading(false);
  };

  useEffect(() => { fetchDomains(); }, [categoryFilter]);

  const filtered = filter
    ? domains.filter(d => d.domain.includes(filter.toLowerCase()) || (d.notes || '').toLowerCase().includes(filter.toLowerCase()))
    : domains;

  const approved = filtered.filter(d => d.is_approved);
  const blocked = filtered.filter(d => !d.is_approved);

  const handleDelete = async (id: string) => {
    if (!confirm('Remove this domain?')) return;
    await api.deleteSafeDomain(id);
    fetchDomains();
  };

  const handleCheck = async () => {
    if (!checkUrl) return;
    setChecking(true);
    try {
      const result = await api.checkURLSafety(checkUrl);
      setCheckResult(result);
    } catch { setCheckResult({ error: 'Failed to check' }); }
    setChecking(false);
  };

  const stats = {
    total: domains.length,
    approved: domains.filter(d => d.is_approved).length,
    blocked: domains.filter(d => !d.is_approved).length,
    categories: Array.from(new Set(domains.map(d => d.category))).length,
  };

  return (
    <AdminShell>
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
              <Shield className="w-6 h-6 text-brand-500" /> Safe Links
            </h1>
            <p className="text-sm text-gray-500 mt-1">
              Manage approved domains for link previews and external link warnings
            </p>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={fetchDomains} className="p-2 rounded-lg border border-warm-300 hover:bg-warm-50 transition-colors">
              <RefreshCw className="w-4 h-4 text-gray-600" />
            </button>
            <button onClick={() => setShowAdd(true)}
              className="px-4 py-2 bg-brand-500 text-white rounded-lg text-sm font-medium hover:bg-brand-600 transition-colors flex items-center gap-2">
              <Plus className="w-4 h-4" /> Add Domain
            </button>
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-4 gap-4 mb-6">
          <div className="bg-white rounded-xl border border-warm-200 p-4">
            <div className="text-2xl font-bold text-gray-900">{stats.total}</div>
            <div className="text-xs text-gray-500">Total Domains</div>
          </div>
          <div className="bg-white rounded-xl border border-warm-200 p-4">
            <div className="text-2xl font-bold text-green-600">{stats.approved}</div>
            <div className="text-xs text-gray-500 flex items-center gap-1"><ShieldCheck className="w-3 h-3" /> Approved</div>
          </div>
          <div className="bg-white rounded-xl border border-warm-200 p-4">
            <div className="text-2xl font-bold text-red-600">{stats.blocked}</div>
            <div className="text-xs text-gray-500 flex items-center gap-1"><ShieldX className="w-3 h-3" /> Blocked</div>
          </div>
          <div className="bg-white rounded-xl border border-warm-200 p-4">
            <div className="text-2xl font-bold text-blue-600">{stats.categories}</div>
            <div className="text-xs text-gray-500">Categories</div>
          </div>
        </div>

        {/* URL Safety Checker */}
        <div className="bg-white rounded-xl border border-warm-200 p-4 mb-6">
          <h2 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
            <Search className="w-4 h-4" /> Check URL Safety
          </h2>
          <div className="flex items-center gap-2">
            <input type="text" value={checkUrl} onChange={(e) => setCheckUrl(e.target.value)}
              placeholder="https://example.com/article"
              onKeyDown={(e) => e.key === 'Enter' && handleCheck()}
              className="flex-1 px-3 py-2 border border-warm-300 rounded-lg text-sm" />
            <button onClick={handleCheck} disabled={checking || !checkUrl}
              className="px-4 py-2 bg-gray-800 text-white rounded-lg text-sm font-medium hover:bg-gray-900 disabled:opacity-50 transition-colors">
              {checking ? 'Checking...' : 'Check'}
            </button>
          </div>
          {checkResult && (
            <div className={`mt-3 p-3 rounded-lg text-sm flex items-center gap-2 ${
              checkResult.safe ? 'bg-green-50 text-green-800 border border-green-200' :
              checkResult.blocked ? 'bg-red-50 text-red-800 border border-red-200' :
              'bg-amber-50 text-amber-800 border border-amber-200'
            }`}>
              {checkResult.safe ? <ShieldCheck className="w-4 h-4" /> :
               checkResult.blocked ? <ShieldX className="w-4 h-4" /> :
               <AlertCircle className="w-4 h-4" />}
              <span className="font-medium">{checkResult.domain}</span> —
              <span className="font-bold uppercase">{checkResult.status}</span>
              {checkResult.category && <span className="text-xs px-2 py-0.5 rounded bg-white/50">{checkResult.category}</span>}
            </div>
          )}
        </div>

        {/* Filters */}
        <div className="flex items-center gap-3 mb-4">
          <div className="relative flex-1">
            <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
            <input type="text" value={filter} onChange={(e) => setFilter(e.target.value)}
              placeholder="Filter domains..."
              className="w-full pl-9 pr-3 py-2 border border-warm-300 rounded-lg text-sm" />
          </div>
          <select value={categoryFilter} onChange={(e) => setCategoryFilter(e.target.value)}
            className="px-3 py-2 border border-warm-300 rounded-lg text-sm bg-white">
            <option value="">All categories</option>
            {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>

        {/* Add Domain Form */}
        {showAdd && <AddDomainForm onSave={() => { setShowAdd(false); fetchDomains(); }} onCancel={() => setShowAdd(false)} />}

        {/* Domain List */}
        {loading ? (
          <div className="text-center py-12 text-gray-500">Loading...</div>
        ) : (
          <div className="bg-white rounded-xl border border-warm-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-warm-50 border-b border-warm-200">
                <tr>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Domain</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Category</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Notes</th>
                  <th className="text-right px-4 py-3 font-medium text-gray-600">Actions</th>
                </tr>
              </thead>
              <tbody>
                {filtered.length === 0 ? (
                  <tr><td colSpan={5} className="text-center py-8 text-gray-400">No domains found</td></tr>
                ) : (
                  filtered.map((d) => (
                    <DomainRow key={d.id} domain={d} onDelete={() => handleDelete(d.id)} onRefresh={fetchDomains} />
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </AdminShell>
  );
}

function DomainRow({ domain: d, onDelete, onRefresh }: { domain: SafeDomain; onDelete: () => void; onRefresh: () => void }) {
  const [editing, setEditing] = useState(false);
  const [category, setCategory] = useState(d.category);
  const [isApproved, setIsApproved] = useState(d.is_approved);
  const [notes, setNotes] = useState(d.notes || '');
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    setSaving(true);
    await api.upsertSafeDomain({ domain: d.domain, category, is_approved: isApproved, notes });
    setSaving(false);
    setEditing(false);
    onRefresh();
  };

  if (editing) {
    return (
      <tr className="border-b border-warm-100 bg-brand-50/30">
        <td className="px-4 py-2 font-mono text-xs">{d.domain}</td>
        <td className="px-4 py-2">
          <select value={category} onChange={(e) => setCategory(e.target.value)} className="px-2 py-1 border border-warm-300 rounded text-xs">
            {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        </td>
        <td className="px-4 py-2">
          <select value={isApproved ? 'true' : 'false'} onChange={(e) => setIsApproved(e.target.value === 'true')}
            className="px-2 py-1 border border-warm-300 rounded text-xs">
            <option value="true">Approved</option>
            <option value="false">Blocked</option>
          </select>
        </td>
        <td className="px-4 py-2">
          <input type="text" value={notes} onChange={(e) => setNotes(e.target.value)}
            className="w-full px-2 py-1 border border-warm-300 rounded text-xs" />
        </td>
        <td className="px-4 py-2 text-right">
          <button onClick={handleSave} disabled={saving} className="text-xs px-2 py-1 bg-brand-500 text-white rounded mr-1">
            {saving ? '...' : 'Save'}
          </button>
          <button onClick={() => setEditing(false)} className="text-xs px-2 py-1 text-gray-500 hover:text-gray-700">Cancel</button>
        </td>
      </tr>
    );
  }

  return (
    <tr className="border-b border-warm-100 hover:bg-warm-50/50 transition-colors cursor-pointer" onClick={() => setEditing(true)}>
      <td className="px-4 py-3">
        <div className="flex items-center gap-2">
          <Globe className="w-3.5 h-3.5 text-gray-400" />
          <span className="font-mono text-xs font-medium">{d.domain}</span>
        </div>
      </td>
      <td className="px-4 py-3">
        <span className="text-xs px-2 py-0.5 rounded-full bg-warm-100 text-gray-600">{d.category}</span>
      </td>
      <td className="px-4 py-3">
        {d.is_approved ? (
          <span className="text-xs px-2 py-0.5 rounded-full bg-green-100 text-green-700 font-medium flex items-center gap-1 w-fit">
            <ShieldCheck className="w-3 h-3" /> Approved
          </span>
        ) : (
          <span className="text-xs px-2 py-0.5 rounded-full bg-red-100 text-red-700 font-medium flex items-center gap-1 w-fit">
            <ShieldX className="w-3 h-3" /> Blocked
          </span>
        )}
      </td>
      <td className="px-4 py-3 text-xs text-gray-500 max-w-[200px] truncate">{d.notes || '—'}</td>
      <td className="px-4 py-3 text-right" onClick={(e) => e.stopPropagation()}>
        <button onClick={onDelete} className="text-red-400 hover:text-red-600 transition-colors p-1">
          <Trash2 className="w-3.5 h-3.5" />
        </button>
      </td>
    </tr>
  );
}

function AddDomainForm({ onSave, onCancel }: { onSave: () => void; onCancel: () => void }) {
  const [domain, setDomain] = useState('');
  const [category, setCategory] = useState('general');
  const [isApproved, setIsApproved] = useState(true);
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!domain.trim()) { setError('Domain is required'); return; }
    setSaving(true);
    setError('');
    try {
      await api.upsertSafeDomain({ domain: domain.trim().toLowerCase(), category, is_approved: isApproved, notes });
      onSave();
    } catch (err: any) {
      setError(err.message || 'Failed to save');
    }
    setSaving(false);
  };

  return (
    <form onSubmit={handleSubmit} className="bg-white rounded-xl border border-warm-200 p-4 mb-4">
      <h3 className="text-sm font-semibold text-gray-700 mb-3">Add Domain</h3>
      <div className="grid grid-cols-4 gap-3">
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Domain</label>
          <input type="text" value={domain} onChange={(e) => setDomain(e.target.value)}
            placeholder="example.com" className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm font-mono" autoFocus />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Category</label>
          <select value={category} onChange={(e) => setCategory(e.target.value)}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm bg-white">
            {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Status</label>
          <select value={isApproved ? 'true' : 'false'} onChange={(e) => setIsApproved(e.target.value === 'true')}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm bg-white">
            <option value="true">✅ Approved</option>
            <option value="false">🚫 Blocked</option>
          </select>
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
          <input type="text" value={notes} onChange={(e) => setNotes(e.target.value)}
            placeholder="Optional description" className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm" />
        </div>
      </div>
      {error && <p className="text-xs text-red-600 mt-2">{error}</p>}
      <div className="flex items-center gap-2 mt-3">
        <button type="submit" disabled={saving}
          className="px-4 py-2 bg-brand-500 text-white rounded-lg text-sm font-medium hover:bg-brand-600 disabled:opacity-50">
          {saving ? 'Saving...' : 'Add Domain'}
        </button>
        <button type="button" onClick={onCancel} className="px-4 py-2 text-gray-600 text-sm hover:text-gray-800">Cancel</button>
      </div>
    </form>
  );
}
