'use client';

import AdminShell from '@/components/AdminShell';
import SelectionBar from '@/components/SelectionBar';
import { api } from '@/lib/api';
import { statusColor, formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Shield, CheckCircle, XCircle, Trash2, Ban, AlertTriangle } from 'lucide-react';

function ScoreBar({ label, value }: { label: string; value: number }) {
  const pct = Math.round(value * 100);
  const color = pct > 70 ? 'bg-red-500' : pct > 40 ? 'bg-yellow-500' : 'bg-green-500';
  return (
    <div className="flex items-center gap-2 text-xs">
      <span className="w-16 text-gray-500">{label}</span>
      <div className="flex-1 h-2 bg-warm-300 rounded-full overflow-hidden">
        <div className={`h-full rounded-full ${color}`} style={{ width: `${pct}%` }} />
      </div>
      <span className="w-8 text-right font-mono text-gray-600">{pct}%</span>
    </div>
  );
}

export default function ModerationPage() {
  const [items, setItems] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('pending');
  const [reviewingId, setReviewingId] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [customReason, setCustomReason] = useState(false);

  const banReasons = [
    'Hate speech or slurs',
    'Harassment or bullying',
    'Spam or scam activity',
    'Posting illegal content',
    'Repeated violations after warnings',
    'Ban evasion (alt account)',
  ];
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkLoading, setBulkLoading] = useState(false);

  const fetchQueue = () => {
    setLoading(true);
    api.getModerationQueue({ limit: 50, status: statusFilter })
      .then((data) => { setItems(data.items); setTotal(data.total); })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchQueue(); }, [statusFilter]);

  const handleReview = async (id: string, action: string) => {
    try {
      await api.reviewModerationFlag(id, action, reason || 'Admin review');
      setReviewingId(null);
      setReason('');
      fetchQueue();
    } catch (e: any) {
      alert(`Action failed: ${e.message}`);
    }
  };

  const toggleSelect = (id: string) => {
    setSelected((prev) => { const s = new Set(prev); s.has(id) ? s.delete(id) : s.add(id); return s; });
  };

  const handleBulkAction = async (action: string) => {
    setBulkLoading(true);
    try {
      await api.bulkReviewModeration(Array.from(selected), action, 'Bulk admin review');
      setSelected(new Set());
      fetchQueue();
    } catch (e: any) {
      alert(`Bulk action failed: ${e.message}`);
    }
    setBulkLoading(false);
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Moderation Queue</h1>
          <p className="text-sm text-gray-500 mt-1">{total} items {statusFilter}</p>
        </div>
        <select className="input w-auto" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="pending">Pending</option>
          <option value="actioned">Actioned</option>
          <option value="dismissed">Dismissed</option>
        </select>
      </div>

      {statusFilter === 'pending' && (
        <SelectionBar
          count={selected.size}
          total={items.length}
          onSelectAll={() => setSelected(new Set(items.map((i) => i.id)))}
          onClearSelection={() => setSelected(new Set())}
          loading={bulkLoading}
          actions={[
            { label: 'Approve All', action: 'approve', color: 'bg-green-50 text-green-700 hover:bg-green-100', icon: <CheckCircle className="w-3.5 h-3.5" /> },
            { label: 'Dismiss All', action: 'dismiss', color: 'bg-gray-100 text-gray-700 hover:bg-gray-200', icon: <XCircle className="w-3.5 h-3.5" /> },
            { label: 'Remove Content', action: 'remove_content', confirm: true, color: 'bg-red-50 text-red-700 hover:bg-red-100', icon: <Trash2 className="w-3.5 h-3.5" /> },
          ]}
          onAction={handleBulkAction}
        />
      )}

      {loading ? (
        <div className="space-y-4">
          {[...Array(3)].map((_, i) => <div key={i} className="card p-6 animate-pulse"><div className="h-20 bg-warm-300 rounded" /></div>)}
        </div>
      ) : items.length === 0 ? (
        <div className="card p-12 text-center">
          <Shield className="w-12 h-12 text-green-400 mx-auto mb-3" />
          <p className="text-gray-500 font-medium">No {statusFilter} items in the queue</p>
          <p className="text-sm text-gray-400 mt-1">All clear! The AI moderation system hasn&apos;t flagged any new content.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {items.map((item) => (
            <div key={item.id} className={`card p-5 ${selected.has(item.id) ? 'ring-2 ring-brand-300' : ''}`}>
              <div className="flex items-start justify-between gap-4">
                <div className="flex items-start gap-3 flex-1">
                  {statusFilter === 'pending' && (
                    <input type="checkbox" className="rounded border-gray-300 mt-1" checked={selected.has(item.id)} onChange={() => toggleSelect(item.id)} />
                  )}
                  <div className="flex-1">
                    {/* Header */}
                    <div className="flex items-center gap-2 mb-2">
                      <span className={`badge ${statusColor(item.status)}`}>{item.status}</span>
                      <span className="badge bg-gray-100 text-gray-600">{item.content_type}</span>
                      <span className="badge bg-red-50 text-red-700">
                        <AlertTriangle className="w-3 h-3 mr-1" />
                        {item.flag_reason}
                      </span>
                      <span className="text-xs text-gray-400">{formatDateTime(item.created_at)}</span>
                    </div>

                    {/* Content */}
                    <div className="bg-warm-100 rounded-lg p-3 mb-3">
                      {item.content_type === 'post' ? (
                        <div>
                          <p className="text-sm text-gray-800 whitespace-pre-wrap">{item.post_body || 'No text content'}</p>
                          {item.post_image && (
                            <div className="mt-2 text-xs text-gray-400">📷 Has image: {item.post_image}</div>
                          )}
                          {item.post_video && (
                            <div className="mt-1 text-xs text-gray-400">🎬 Has video: {item.post_video}</div>
                          )}
                        </div>
                      ) : (
                        <p className="text-sm text-gray-800">{item.comment_body || 'No content'}</p>
                      )}
                    </div>

                    {/* Author */}
                    <p className="text-xs text-gray-500 mb-3">
                      By <span className="font-medium text-gray-700">@{item.author_handle || '—'}</span>
                      {item.author_name && ` (${item.author_name})`}
                    </p>

                    {/* AI Scores */}
                    {item.scores && (
                      <div className="space-y-1 max-w-xs">
                        {item.scores.hate != null && <ScoreBar label="Hate" value={item.scores.hate} />}
                        {item.scores.greed != null && <ScoreBar label="Greed" value={item.scores.greed} />}
                        {item.scores.delusion != null && <ScoreBar label="Delusion" value={item.scores.delusion} />}
                      </div>
                    )}
                  </div>
                </div>

                {/* Actions */}
                {item.status === 'pending' && (
                  <div className="flex flex-col gap-2 flex-shrink-0">
                    <button
                      onClick={() => handleReview(item.id, 'approve')}
                      className="flex items-center gap-1.5 px-3 py-2 bg-green-50 text-green-700 rounded-lg text-xs font-medium hover:bg-green-100"
                    >
                      <CheckCircle className="w-4 h-4" /> Approve
                    </button>
                    <button
                      onClick={() => handleReview(item.id, 'dismiss')}
                      className="flex items-center gap-1.5 px-3 py-2 bg-gray-50 text-gray-600 rounded-lg text-xs font-medium hover:bg-gray-100"
                    >
                      <XCircle className="w-4 h-4" /> Dismiss
                    </button>
                    <button
                      onClick={() => handleReview(item.id, 'remove_content')}
                      className="flex items-center gap-1.5 px-3 py-2 bg-red-50 text-red-700 rounded-lg text-xs font-medium hover:bg-red-100"
                    >
                      <Trash2 className="w-4 h-4" /> Remove
                    </button>
                    <button
                      onClick={() => setReviewingId(item.id)}
                      className="flex items-center gap-1.5 px-3 py-2 bg-red-100 text-red-800 rounded-lg text-xs font-medium hover:bg-red-200"
                    >
                      <Ban className="w-4 h-4" /> Ban User
                    </button>
                  </div>
                )}
              </div>

              {/* Ban modal inline */}
              {reviewingId === item.id && (
                <div className="mt-4 p-4 bg-red-50 border border-red-200 rounded-lg">
                  <p className="text-sm font-medium text-red-800 mb-2">Ban user and remove content</p>
                  <div className="space-y-1.5 mb-3">
                    {banReasons.map((preset) => (
                      <button
                        key={preset}
                        onClick={() => { setReason(preset); setCustomReason(false); }}
                        className={`w-full text-left px-3 py-1.5 rounded text-xs border transition-colors ${
                          reason === preset && !customReason
                            ? 'border-red-400 bg-red-100 text-red-800 font-medium'
                            : 'border-red-200 hover:border-red-300 text-red-700'
                        }`}
                      >
                        {preset}
                      </button>
                    ))}
                    <button
                      onClick={() => { setCustomReason(true); setReason(''); }}
                      className={`w-full text-left px-3 py-1.5 rounded text-xs border transition-colors ${
                        customReason
                          ? 'border-red-400 bg-red-100 text-red-800 font-medium'
                          : 'border-red-200 hover:border-red-300 text-red-700'
                      }`}
                    >
                      Custom reason...
                    </button>
                  </div>
                  {customReason && (
                    <input className="input mb-2 text-sm" placeholder="Enter custom reason..." value={reason} onChange={(e) => setReason(e.target.value)} autoFocus />
                  )}
                  <div className="flex gap-2">
                    <button onClick={() => { setReviewingId(null); setReason(''); setCustomReason(false); }} className="btn-secondary text-xs">Cancel</button>
                    <button onClick={() => handleReview(item.id, 'ban_user')} className="btn-danger text-xs" disabled={!reason.trim()}>Confirm Ban</button>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </AdminShell>
  );
}
