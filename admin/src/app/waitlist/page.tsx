// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import PerPageSelect from '@/components/PerPageSelect';
import { api } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { useEffect, useRef, useState } from 'react';
import { Users, RefreshCw, CheckCircle, XCircle, Trash2, ChevronLeft, ChevronRight, Upload, Mail, Send, X } from 'lucide-react';

const STATUS_COLORS: Record<string, string> = {
  pending:  'bg-yellow-100 text-yellow-700',
  approved: 'bg-green-100 text-green-700',
  rejected: 'bg-red-100 text-red-700',
  invited:  'bg-blue-100 text-blue-700',
};

// ─── Import CSV Modal ─────────────────────────────────────────────────────────

function ImportModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [rows, setRows] = useState<Array<{ email: string; name?: string; status?: string }>>([]);
  const [parseError, setParseError] = useState('');
  const [result, setResult] = useState<{ imported: number; skipped: number; errors: string[] } | null>(null);
  const [loading, setLoading] = useState(false);

  const handleFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    setParseError('');
    setResult(null);
    setRows([]);
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      const text = (ev.target?.result as string) || '';
      const lines = text.split(/\r?\n/).filter((l) => l.trim());
      if (!lines.length) { setParseError('File is empty.'); return; }
      // Detect header row
      const firstLower = lines[0].toLowerCase();
      const hasHeader = firstLower.includes('email');
      const dataLines = hasHeader ? lines.slice(1) : lines;
      const parsed: Array<{ email: string; name?: string; status?: string }> = [];
      for (const line of dataLines) {
        // Support comma or tab separated
        const cols = line.includes('\t') ? line.split('\t') : line.split(',');
        const email = cols[0]?.replace(/"/g, '').trim().toLowerCase();
        if (!email || !email.includes('@')) continue;
        const name = cols[1]?.replace(/"/g, '').trim() || undefined;
        const status = cols[2]?.replace(/"/g, '').trim() || undefined;
        parsed.push({ email, name: name || undefined, status: status || undefined });
      }
      if (!parsed.length) { setParseError('No valid email addresses found.'); return; }
      setRows(parsed);
    };
    reader.readAsText(file);
  };

  const handleImport = async () => {
    if (!rows.length) return;
    setLoading(true);
    try {
      const res = await api.importWaitlist(rows);
      setResult(res);
      onDone();
    } catch (e: any) {
      setParseError(e.message || 'Import failed.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={onClose}>
      <div className="card p-6 w-full max-w-lg mx-4 max-h-[80vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-base font-semibold text-gray-900 flex items-center gap-2">
            <Upload className="w-4 h-4 text-brand-500" /> Import CSV
          </h3>
          <button type="button" title="Close" onClick={onClose} className="p-1 rounded hover:bg-warm-100 text-gray-400"><X className="w-4 h-4" /></button>
        </div>

        {!result ? (
          <>
            <p className="text-sm text-gray-500 mb-4">
              Upload a CSV file with columns: <span className="font-mono text-xs bg-warm-100 px-1 py-0.5 rounded">email, name (optional), status (optional)</span>.
              A header row is auto-detected. Max 5,000 rows.
            </p>
            <input
              ref={fileRef}
              type="file"
              accept=".csv,.txt,.tsv"
              aria-label="Upload CSV file"
              onChange={handleFile}
              className="block w-full text-sm text-gray-600 file:mr-3 file:py-2 file:px-4 file:rounded file:border-0 file:text-sm file:font-medium file:bg-brand-50 file:text-brand-700 hover:file:bg-brand-100 mb-3"
            />
            {parseError && <p className="text-sm text-red-500 mb-3">{parseError}</p>}
            {rows.length > 0 && (
              <>
                <p className="text-sm font-medium text-gray-700 mb-2">{rows.length} rows parsed — preview:</p>
                <div className="overflow-x-auto rounded border border-warm-200 mb-4">
                  <table className="w-full text-xs">
                    <thead className="bg-warm-100">
                      <tr>
                        <th className="px-3 py-2 text-left font-medium text-gray-600">Email</th>
                        <th className="px-3 py-2 text-left font-medium text-gray-600">Name</th>
                        <th className="px-3 py-2 text-left font-medium text-gray-600">Status</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-warm-100">
                      {rows.slice(0, 5).map((r, i) => (
                        <tr key={i}>
                          <td className="px-3 py-1.5 text-gray-900">{r.email}</td>
                          <td className="px-3 py-1.5 text-gray-500">{r.name || '—'}</td>
                          <td className="px-3 py-1.5 text-gray-500">{r.status || 'pending'}</td>
                        </tr>
                      ))}
                      {rows.length > 5 && (
                        <tr><td colSpan={3} className="px-3 py-1.5 text-gray-400">…and {rows.length - 5} more</td></tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </>
            )}
            <div className="flex gap-2 justify-end">
              <button onClick={onClose} className="btn-secondary text-sm">Cancel</button>
              <button
                onClick={handleImport}
                disabled={!rows.length || loading}
                className="btn-primary text-sm flex items-center gap-1.5"
              >
                {loading ? 'Importing…' : <><Upload className="w-3.5 h-3.5" /> Import {rows.length > 0 ? rows.length : ''} Rows</>}
              </button>
            </div>
          </>
        ) : (
          <div className="text-center py-4">
            <CheckCircle className="w-10 h-10 text-green-500 mx-auto mb-3" />
            <p className="text-base font-semibold text-gray-900 mb-1">Import Complete</p>
            <p className="text-sm text-gray-600 mb-1"><span className="font-medium text-green-600">{result.imported}</span> imported</p>
            <p className="text-sm text-gray-600 mb-3"><span className="font-medium text-gray-500">{result.skipped}</span> skipped (duplicates)</p>
            {result.errors?.length > 0 && (
              <details className="text-left text-xs text-red-500 mb-3">
                <summary className="cursor-pointer">{result.errors.length} errors</summary>
                <ul className="mt-1 space-y-0.5 pl-3">{result.errors.map((er, i) => <li key={i}>{er}</li>)}</ul>
              </details>
            )}
            <button onClick={onClose} className="btn-primary text-sm">Done</button>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Email Blast Modal ────────────────────────────────────────────────────────

const DEFAULT_BUTTON_COLOR = '#4f46e5';

function BlastModal({ onClose }: { onClose: () => void }) {
  const [tab, setTab] = useState<'compose' | 'preview' | 'confirm'>('compose');
  const [statusFilter, setStatusFilter] = useState('pending');
  const [subject, setSubject] = useState('');
  const [title, setTitle] = useState('');
  const [header, setHeader] = useState('');
  const [content, setContent] = useState('');
  const [buttonText, setButtonText] = useState('');
  const [buttonUrl, setButtonUrl] = useState('');
  const [buttonColor, setButtonColor] = useState(DEFAULT_BUTTON_COLOR);
  const [footer, setFooter] = useState('');
  const [result, setResult] = useState<{ sent: number; failed: number } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const previewHtml = `
    <div style="font-family:sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#111">
      ${header ? `<p style="font-size:14px;color:#6b7280;margin-bottom:16px">${header}</p>` : ''}
      <h2 style="font-size:22px;font-weight:700;margin-bottom:12px">${title || '(title)'}</h2>
      <div style="font-size:15px;line-height:1.6;white-space:pre-wrap">${content || '(content)'}</div>
      ${buttonText && buttonUrl ? `
        <div style="margin-top:24px">
          <a href="${buttonUrl}" style="display:inline-block;background:${buttonColor};color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;font-size:14px">${buttonText}</a>
        </div>` : ''}
      ${footer ? `<p style="margin-top:24px;font-size:12px;color:#9ca3af">${footer}</p>` : ''}
    </div>
  `;

  const handleSend = async () => {
    if (!subject.trim() || !title.trim() || !content.trim()) {
      setError('Subject, title, and content are required.');
      return;
    }
    setLoading(true);
    setError('');
    try {
      const res = await api.emailBlastWaitlist({
        status_filter: statusFilter,
        subject: subject.trim(),
        title: title.trim(),
        header: header.trim() || undefined,
        content: content.trim(),
        button_text: buttonText.trim() || undefined,
        button_url: buttonUrl.trim() || undefined,
        button_color: buttonColor !== DEFAULT_BUTTON_COLOR ? buttonColor : undefined,
        footer: footer.trim() || undefined,
      });
      setResult(res);
      setTab('confirm');
    } catch (e: any) {
      setError(e.message || 'Send failed.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={onClose}>
      <div className="card p-6 w-full max-w-2xl mx-4 max-h-[90vh] flex flex-col" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4 flex-shrink-0">
          <h3 className="text-base font-semibold text-gray-900 flex items-center gap-2">
            <Mail className="w-4 h-4 text-brand-500" /> Email Blast
          </h3>
          <button type="button" title="Close" onClick={onClose} className="p-1 rounded hover:bg-warm-100 text-gray-400"><X className="w-4 h-4" /></button>
        </div>

        {/* Tabs */}
        {tab !== 'confirm' && (
          <div className="flex gap-1 mb-4 border-b border-warm-200 flex-shrink-0">
            {(['compose', 'preview'] as const).map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
                  tab === t ? 'border-brand-500 text-brand-600' : 'border-transparent text-gray-500 hover:text-gray-700'
                }`}
              >
                {t.charAt(0).toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>
        )}

        <div className="overflow-y-auto flex-1">
          {tab === 'compose' && (
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Audience</label>
                  <select
                    value={statusFilter}
                    onChange={(e) => setStatusFilter(e.target.value)}
                    aria-label="Audience status filter"
                    className="input w-full text-sm"
                  >
                    <option value="all">All statuses</option>
                    <option value="pending">Pending</option>
                    <option value="approved">Approved</option>
                    <option value="invited">Invited</option>
                    <option value="rejected">Rejected</option>
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Subject *</label>
                  <input
                    className="input w-full text-sm"
                    placeholder="Email subject line"
                    value={subject}
                    onChange={(e) => setSubject(e.target.value)}
                  />
                </div>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Pre-header (preview text)</label>
                <input
                  className="input w-full text-sm"
                  placeholder="Short text shown in inbox previews"
                  value={header}
                  onChange={(e) => setHeader(e.target.value)}
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Title *</label>
                <input
                  className="input w-full text-sm"
                  placeholder="Email heading"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Content *</label>
                <textarea
                  className="input w-full text-sm"
                  rows={6}
                  placeholder="Email body (plain text, line breaks preserved)"
                  value={content}
                  onChange={(e) => setContent(e.target.value)}
                />
              </div>
              <div className="grid grid-cols-3 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Button text</label>
                  <input
                    className="input w-full text-sm"
                    placeholder="e.g. Join the Beta"
                    value={buttonText}
                    onChange={(e) => setButtonText(e.target.value)}
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Button URL</label>
                  <input
                    className="input w-full text-sm"
                    placeholder="https://..."
                    value={buttonUrl}
                    onChange={(e) => setButtonUrl(e.target.value)}
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">Button color</label>
                  <input
                    type="color"
                    aria-label="Button color"
                    className="h-9 w-full rounded border border-warm-300 cursor-pointer"
                    value={buttonColor}
                    onChange={(e) => setButtonColor(e.target.value)}
                  />
                </div>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Footer</label>
                <input
                  className="input w-full text-sm"
                  placeholder="e.g. You're receiving this because you signed up for the Sojorn beta."
                  value={footer}
                  onChange={(e) => setFooter(e.target.value)}
                />
              </div>
            </div>
          )}

          {tab === 'preview' && (
            <div>
              <p className="text-xs text-gray-400 mb-3">Approximate preview — actual rendering varies by email client.</p>
              <div
                className="rounded-lg border border-warm-200 bg-white p-4 text-sm"
                dangerouslySetInnerHTML={{ __html: previewHtml }}
              />
            </div>
          )}

          {tab === 'confirm' && result && (
            <div className="text-center py-6">
              <Send className="w-10 h-10 text-green-500 mx-auto mb-3" />
              <p className="text-base font-semibold text-gray-900 mb-1">Blast Sent</p>
              <p className="text-sm text-gray-600 mb-1"><span className="font-medium text-green-600">{result.sent}</span> emails sent</p>
              {result.failed > 0 && (
                <p className="text-sm text-red-500 mb-1">{result.failed} failed</p>
              )}
              <button onClick={onClose} className="btn-primary text-sm mt-4">Done</button>
            </div>
          )}
        </div>

        {tab !== 'confirm' && (
          <div className="flex items-center justify-between pt-4 border-t border-warm-200 flex-shrink-0 mt-4">
            {error && <p className="text-sm text-red-500">{error}</p>}
            {!error && <span />}
            <div className="flex gap-2">
              <button onClick={onClose} className="btn-secondary text-sm">Cancel</button>
              {tab === 'compose' && (
                <button onClick={() => setTab('preview')} className="btn-secondary text-sm">Preview →</button>
              )}
              {tab === 'preview' && (
                <button
                  onClick={handleSend}
                  disabled={loading || !subject.trim() || !title.trim() || !content.trim()}
                  className="btn-primary text-sm flex items-center gap-1.5"
                >
                  {loading ? 'Sending…' : <><Send className="w-3.5 h-3.5" /> Send Blast</>}
                </button>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function WaitlistPage() {
  const [entries, setEntries] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(0);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [notesModal, setNotesModal] = useState<{ id: string; notes: string } | null>(null);
  const [limit, setLimit] = useState(50);
  const [showImport, setShowImport] = useState(false);
  const [showBlast, setShowBlast] = useState(false);

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

  useEffect(() => { fetchList(page, statusFilter); }, [page, statusFilter, limit]);

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

  return (
    <AdminOnlyGuard>
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
        <div className="flex items-center gap-2">
          <button type="button" onClick={() => setShowImport(true)} className="btn-secondary text-sm flex items-center gap-1.5">
            <Upload className="w-4 h-4" /> Import CSV
          </button>
          <button type="button" onClick={() => setShowBlast(true)} className="btn-secondary text-sm flex items-center gap-1.5">
            <Mail className="w-4 h-4" /> Email Blast
          </button>
          <button type="button" onClick={() => fetchList()} className="btn-secondary text-sm flex items-center gap-1">
            <RefreshCw className="w-4 h-4" /> Refresh
          </button>
        </div>
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
        <div className="flex items-center justify-between px-4 py-3 border-t border-warm-200">
          <p className="text-xs text-gray-500">Page {page + 1} of {totalPages}</p>
          <div className="flex items-center gap-3">
            <PerPageSelect value={limit} onChange={(n) => { setLimit(n); setPage(0); }} />
            <button
              type="button"
              title="Previous page"
              onClick={() => setPage((p) => Math.max(0, p - 1))}
              disabled={page === 0}
              className="p-1.5 rounded border border-warm-300 disabled:opacity-40 hover:bg-warm-100"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <button
              type="button"
              title="Next page"
              onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
              disabled={page >= totalPages - 1}
              className="p-1.5 rounded border border-warm-300 disabled:opacity-40 hover:bg-warm-100"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>
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

      {/* Import Modal */}
      {showImport && (
        <ImportModal
          onClose={() => setShowImport(false)}
          onDone={() => fetchList()}
        />
      )}

      {/* Blast Modal */}
      {showBlast && (
        <BlastModal onClose={() => setShowBlast(false)} />
      )}
    </AdminShell>
    </AdminOnlyGuard>
  );
}
