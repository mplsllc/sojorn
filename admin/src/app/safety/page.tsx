'use client';

import AdminShell from '@/components/AdminShell';
import SelectionBar from '@/components/SelectionBar';
import { api } from '@/lib/api';
import { statusColor, formatDateTime } from '@/lib/utils';
import { useEffect, useState, useCallback } from 'react';
import {
  Shield, CheckCircle, XCircle, Trash2, Ban, AlertTriangle, Scale, Flag,
  RefreshCw, ChevronDown, ChevronUp, User, Clock, ExternalLink,
} from 'lucide-react';
import Link from 'next/link';

type Tab = 'moderation' | 'appeals' | 'reports';

// ─── Score Bar ────────────────────────────────────────
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

// ─── User Context Panel ───────────────────────────────
function UserContextPanel({ userId, handle }: { userId?: string; handle?: string }) {
  const [user, setUser] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);

  const fetchUser = useCallback(async () => {
    if (!userId) return;
    setLoading(true);
    try {
      const data = await api.getUser(userId);
      setUser(data);
    } catch {}
    setLoading(false);
  }, [userId]);

  useEffect(() => {
    if (open && !user && userId) fetchUser();
  }, [open, user, userId, fetchUser]);

  if (!userId) return null;

  return (
    <div className="mt-2">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-1.5 text-xs text-brand-600 hover:text-brand-800 transition-colors"
      >
        <User className="w-3 h-3" />
        <span>@{handle || 'unknown'}</span>
        {open ? <ChevronUp className="w-3 h-3" /> : <ChevronDown className="w-3 h-3" />}
      </button>
      {open && (
        <div className="mt-2 p-3 bg-warm-50 border border-warm-200 rounded-lg text-xs space-y-1.5">
          {loading ? (
            <p className="text-gray-400">Loading user context...</p>
          ) : user ? (
            <>
              <div className="flex items-center gap-2">
                <span className="font-medium text-gray-700">{user.display_name || user.handle}</span>
                <span className={`px-1.5 py-0.5 rounded text-[10px] font-medium ${
                  user.status === 'active' ? 'bg-green-100 text-green-700' :
                  user.status === 'suspended' ? 'bg-red-100 text-red-700' :
                  'bg-yellow-100 text-yellow-700'
                }`}>{user.status}</span>
              </div>
              {user.violation_count != null && (
                <p className="text-gray-500">
                  Violations: <span className={`font-medium ${user.violation_count > 0 ? 'text-red-600' : 'text-green-600'}`}>{user.violation_count}</span>
                  {user.warning_count > 0 && <span className="ml-2">Warnings: <span className="font-medium text-yellow-600">{user.warning_count}</span></span>}
                </p>
              )}
              {user.created_at && (
                <p className="text-gray-400">Joined {formatDateTime(user.created_at)}</p>
              )}
              <Link href={`/users/${userId}`} className="inline-flex items-center gap-1 text-brand-500 hover:text-brand-700">
                View full profile <ExternalLink className="w-3 h-3" />
              </Link>
            </>
          ) : (
            <p className="text-gray-400">User not found</p>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Tab Badge ────────────────────────────────────────
function TabBadge({ count }: { count: number }) {
  if (count === 0) return null;
  return (
    <span className="ml-1.5 px-1.5 py-0.5 text-[10px] font-bold rounded-full bg-red-500 text-white min-w-[18px] text-center">
      {count > 99 ? '99+' : count}
    </span>
  );
}

// ─── Main Page ────────────────────────────────────────
export default function SafetyWorkspacePage() {
  const [tab, setTab] = useState<Tab>('moderation');

  // Moderation state
  const [modItems, setModItems] = useState<any[]>([]);
  const [modTotal, setModTotal] = useState(0);
  const [modLoading, setModLoading] = useState(true);
  const [modStatus, setModStatus] = useState('pending');
  const [modSelected, setModSelected] = useState<Set<string>>(new Set());
  const [modBulkLoading, setModBulkLoading] = useState(false);
  const [reviewingId, setReviewingId] = useState<string | null>(null);
  const [banReason, setBanReason] = useState('');
  const [customBanReason, setCustomBanReason] = useState(false);

  // Appeals state
  const [appeals, setAppeals] = useState<any[]>([]);
  const [appealsTotal, setAppealsTotal] = useState(0);
  const [appealsLoading, setAppealsLoading] = useState(true);
  const [appealsStatus, setAppealsStatus] = useState('pending');
  const [appealReviewId, setAppealReviewId] = useState<string | null>(null);
  const [appealDecision, setAppealDecision] = useState('');
  const [restoreContent, setRestoreContent] = useState(false);

  // Reports state
  const [reports, setReports] = useState<any[]>([]);
  const [reportsTotal, setReportsTotal] = useState(0);
  const [reportsLoading, setReportsLoading] = useState(true);
  const [reportsStatus, setReportsStatus] = useState('pending');
  const [reportsSelected, setReportsSelected] = useState<Set<string>>(new Set());
  const [reportsBulkLoading, setReportsBulkLoading] = useState(false);

  // Pending counts for badges
  const [pendingCounts, setPendingCounts] = useState({ moderation: 0, appeals: 0, reports: 0 });

  const banReasons = [
    'Hate speech or slurs',
    'Harassment or bullying',
    'Spam or scam activity',
    'Posting illegal content',
    'Repeated violations after warnings',
    'Ban evasion (alt account)',
  ];

  // ── Fetch functions ──
  const fetchModeration = useCallback(() => {
    setModLoading(true);
    api.getModerationQueue({ limit: 50, status: modStatus })
      .then((data) => { setModItems(data.items || []); setModTotal(data.total || 0); })
      .catch(() => {})
      .finally(() => setModLoading(false));
  }, [modStatus]);

  const fetchAppeals = useCallback(() => {
    setAppealsLoading(true);
    api.listAppeals({ limit: 50, status: appealsStatus })
      .then((data) => { setAppeals(data.appeals || []); setAppealsTotal(data.total || 0); })
      .catch(() => {})
      .finally(() => setAppealsLoading(false));
  }, [appealsStatus]);

  const fetchReports = useCallback(() => {
    setReportsLoading(true);
    api.listReports({ limit: 50, status: reportsStatus })
      .then((data) => { setReports(data.reports || []); setReportsTotal(data.total || 0); })
      .catch(() => {})
      .finally(() => setReportsLoading(false));
  }, [reportsStatus]);

  const fetchPendingCounts = useCallback(() => {
    Promise.allSettled([
      api.getModerationQueue({ limit: 1, status: 'pending' }),
      api.listAppeals({ limit: 1, status: 'pending' }),
      api.listReports({ limit: 1, status: 'pending' }),
    ]).then(([mod, app, rep]) => {
      setPendingCounts({
        moderation: mod.status === 'fulfilled' ? (mod.value.total || 0) : 0,
        appeals: app.status === 'fulfilled' ? (app.value.total || 0) : 0,
        reports: rep.status === 'fulfilled' ? (rep.value.total || 0) : 0,
      });
    });
  }, []);

  useEffect(() => { fetchPendingCounts(); }, [fetchPendingCounts]);
  useEffect(() => { fetchModeration(); }, [fetchModeration]);
  useEffect(() => { fetchAppeals(); }, [fetchAppeals]);
  useEffect(() => { fetchReports(); }, [fetchReports]);

  const refreshAll = () => {
    fetchModeration();
    fetchAppeals();
    fetchReports();
    fetchPendingCounts();
  };

  // ── Moderation actions ──
  const handleModReview = async (id: string, action: string) => {
    try {
      await api.reviewModerationFlag(id, action, banReason || 'Admin review');
      setReviewingId(null);
      setBanReason('');
      fetchModeration();
      fetchPendingCounts();
    } catch (e: any) {
      alert(`Action failed: ${e.message}`);
    }
  };

  const handleModBulk = async (action: string) => {
    setModBulkLoading(true);
    try {
      await api.bulkReviewModeration(Array.from(modSelected), action, 'Bulk admin review');
      setModSelected(new Set());
      fetchModeration();
      fetchPendingCounts();
    } catch (e: any) {
      alert(`Bulk action failed: ${e.message}`);
    }
    setModBulkLoading(false);
  };

  // ── Appeal actions ──
  const handleAppealReview = async (id: string, decision: 'approved' | 'rejected') => {
    if (!appealDecision.trim()) return;
    try {
      await api.reviewAppeal(id, decision, appealDecision, restoreContent);
      setAppealReviewId(null);
      setAppealDecision('');
      setRestoreContent(false);
      fetchAppeals();
      fetchPendingCounts();
    } catch {}
  };

  // ── Report actions ──
  const handleReportUpdate = async (id: string, status: string) => {
    try {
      await api.updateReportStatus(id, status);
      fetchReports();
      fetchPendingCounts();
    } catch {}
  };

  const handleReportsBulk = async (action: string) => {
    setReportsBulkLoading(true);
    try {
      await api.bulkUpdateReports(Array.from(reportsSelected), action);
      setReportsSelected(new Set());
      fetchReports();
      fetchPendingCounts();
    } catch {}
    setReportsBulkLoading(false);
  };

  const totalPending = pendingCounts.moderation + pendingCounts.appeals + pendingCounts.reports;

  return (
    <AdminShell>
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Shield className="w-6 h-6 text-brand-500" />
            Safety Workspace
            {totalPending > 0 && (
              <span className="ml-2 px-2 py-0.5 text-xs font-bold rounded-full bg-red-500 text-white">
                {totalPending} pending
              </span>
            )}
          </h1>
          <p className="text-sm text-gray-500 mt-1">Unified moderation, appeals, and reports management</p>
        </div>
        <button onClick={refreshAll} className="flex items-center gap-2 px-3 py-2 text-sm border border-warm-300 rounded-lg hover:bg-warm-200 transition-colors">
          <RefreshCw className="w-4 h-4" /> Refresh All
        </button>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-warm-300 mb-6">
        {([
          ['moderation', 'Moderation Queue', Shield, pendingCounts.moderation],
          ['appeals', 'Appeals', Scale, pendingCounts.appeals],
          ['reports', 'Reports', Flag, pendingCounts.reports],
        ] as const).map(([key, label, Icon, count]) => (
          <button
            key={key}
            onClick={() => setTab(key as Tab)}
            className={`flex items-center gap-2 px-5 py-3 text-sm font-medium border-b-2 transition-colors ${
              tab === key
                ? 'border-brand-500 text-brand-700 bg-brand-50/50'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-warm-400'
            }`}
          >
            <Icon className="w-4 h-4" />
            {label}
            <TabBadge count={count as number} />
          </button>
        ))}
      </div>

      {/* ═══ MODERATION TAB ═══ */}
      {tab === 'moderation' && (
        <div>
          <div className="flex items-center justify-between mb-4">
            <p className="text-sm text-gray-500">{modTotal} items {modStatus}</p>
            <select className="input w-auto text-sm" value={modStatus} onChange={(e) => { setModStatus(e.target.value); setModSelected(new Set()); }}>
              <option value="pending">Pending</option>
              <option value="actioned">Actioned</option>
              <option value="dismissed">Dismissed</option>
            </select>
          </div>

          {modStatus === 'pending' && (
            <SelectionBar
              count={modSelected.size}
              total={modItems.length}
              onSelectAll={() => setModSelected(new Set(modItems.map((i) => i.id)))}
              onClearSelection={() => setModSelected(new Set())}
              loading={modBulkLoading}
              actions={[
                { label: 'Approve All', action: 'approve', color: 'bg-green-50 text-green-700 hover:bg-green-100', icon: <CheckCircle className="w-3.5 h-3.5" /> },
                { label: 'Dismiss All', action: 'dismiss', color: 'bg-gray-100 text-gray-700 hover:bg-gray-200', icon: <XCircle className="w-3.5 h-3.5" /> },
                { label: 'Remove Content', action: 'remove_content', confirm: true, color: 'bg-red-50 text-red-700 hover:bg-red-100', icon: <Trash2 className="w-3.5 h-3.5" /> },
              ]}
              onAction={handleModBulk}
            />
          )}

          {modLoading ? (
            <div className="space-y-4">
              {[...Array(3)].map((_, i) => <div key={i} className="card p-6 animate-pulse"><div className="h-20 bg-warm-300 rounded" /></div>)}
            </div>
          ) : modItems.length === 0 ? (
            <div className="card p-12 text-center">
              <Shield className="w-12 h-12 text-green-400 mx-auto mb-3" />
              <p className="text-gray-500 font-medium">No {modStatus} items in the queue</p>
              <p className="text-sm text-gray-400 mt-1">All clear!</p>
            </div>
          ) : (
            <div className="space-y-4">
              {modItems.map((item) => (
                <div key={item.id} className={`card p-5 ${modSelected.has(item.id) ? 'ring-2 ring-brand-300' : ''}`}>
                  <div className="flex items-start justify-between gap-4">
                    <div className="flex items-start gap-3 flex-1">
                      {modStatus === 'pending' && (
                        <input type="checkbox" className="rounded border-gray-300 mt-1" checked={modSelected.has(item.id)}
                          onChange={() => setModSelected((prev) => { const s = new Set(prev); s.has(item.id) ? s.delete(item.id) : s.add(item.id); return s; })} />
                      )}
                      <div className="flex-1">
                        <div className="flex items-center gap-2 mb-2">
                          <span className={`badge ${statusColor(item.status)}`}>{item.status}</span>
                          <span className="badge bg-gray-100 text-gray-600">{item.content_type}</span>
                          <span className="badge bg-red-50 text-red-700">
                            <AlertTriangle className="w-3 h-3 mr-1" />{item.flag_reason}
                          </span>
                          <span className="text-xs text-gray-400 flex items-center gap-1"><Clock className="w-3 h-3" />{formatDateTime(item.created_at)}</span>
                        </div>

                        <div className="bg-warm-100 rounded-lg p-3 mb-3">
                          {item.content_type === 'post' ? (
                            <div>
                              <p className="text-sm text-gray-800 whitespace-pre-wrap">{item.post_body || 'No text content'}</p>
                              {item.post_image && <div className="mt-2 text-xs text-gray-400">Has image: {item.post_image}</div>}
                              {item.post_video && <div className="mt-1 text-xs text-gray-400">Has video: {item.post_video}</div>}
                            </div>
                          ) : (
                            <p className="text-sm text-gray-800">{item.comment_body || 'No content'}</p>
                          )}
                        </div>

                        {/* Contextual user info */}
                        <UserContextPanel userId={item.author_id} handle={item.author_handle} />

                        {item.scores && (
                          <div className="space-y-1 max-w-xs mt-3">
                            {item.scores.hate != null && <ScoreBar label="Hate" value={item.scores.hate} />}
                            {item.scores.greed != null && <ScoreBar label="Greed" value={item.scores.greed} />}
                            {item.scores.delusion != null && <ScoreBar label="Delusion" value={item.scores.delusion} />}
                          </div>
                        )}
                      </div>
                    </div>

                    {item.status === 'pending' && (
                      <div className="flex flex-col gap-2 flex-shrink-0">
                        <button onClick={() => handleModReview(item.id, 'approve')}
                          className="flex items-center gap-1.5 px-3 py-2 bg-green-50 text-green-700 rounded-lg text-xs font-medium hover:bg-green-100">
                          <CheckCircle className="w-4 h-4" /> Approve
                        </button>
                        <button onClick={() => handleModReview(item.id, 'dismiss')}
                          className="flex items-center gap-1.5 px-3 py-2 bg-gray-50 text-gray-600 rounded-lg text-xs font-medium hover:bg-gray-100">
                          <XCircle className="w-4 h-4" /> Dismiss
                        </button>
                        <button onClick={() => handleModReview(item.id, 'remove_content')}
                          className="flex items-center gap-1.5 px-3 py-2 bg-red-50 text-red-700 rounded-lg text-xs font-medium hover:bg-red-100">
                          <Trash2 className="w-4 h-4" /> Remove
                        </button>
                        <button onClick={() => setReviewingId(item.id)}
                          className="flex items-center gap-1.5 px-3 py-2 bg-red-100 text-red-800 rounded-lg text-xs font-medium hover:bg-red-200">
                          <Ban className="w-4 h-4" /> Ban User
                        </button>
                      </div>
                    )}
                  </div>

                  {reviewingId === item.id && (
                    <div className="mt-4 p-4 bg-red-50 border border-red-200 rounded-lg">
                      <p className="text-sm font-medium text-red-800 mb-2">Ban user and remove content</p>
                      <div className="space-y-1.5 mb-3">
                        {banReasons.map((preset) => (
                          <button key={preset}
                            onClick={() => { setBanReason(preset); setCustomBanReason(false); }}
                            className={`w-full text-left px-3 py-1.5 rounded text-xs border transition-colors ${
                              banReason === preset && !customBanReason
                                ? 'border-red-400 bg-red-100 text-red-800 font-medium'
                                : 'border-red-200 hover:border-red-300 text-red-700'
                            }`}>{preset}</button>
                        ))}
                        <button onClick={() => { setCustomBanReason(true); setBanReason(''); }}
                          className={`w-full text-left px-3 py-1.5 rounded text-xs border transition-colors ${
                            customBanReason ? 'border-red-400 bg-red-100 text-red-800 font-medium' : 'border-red-200 hover:border-red-300 text-red-700'
                          }`}>Custom reason...</button>
                      </div>
                      {customBanReason && (
                        <input className="input mb-2 text-sm" placeholder="Enter custom reason..." value={banReason} onChange={(e) => setBanReason(e.target.value)} autoFocus />
                      )}
                      <div className="flex gap-2">
                        <button onClick={() => { setReviewingId(null); setBanReason(''); setCustomBanReason(false); }} className="btn-secondary text-xs">Cancel</button>
                        <button onClick={() => handleModReview(item.id, 'ban_user')} className="btn-danger text-xs" disabled={!banReason.trim()}>Confirm Ban</button>
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ═══ APPEALS TAB ═══ */}
      {tab === 'appeals' && (
        <div>
          <div className="flex items-center justify-between mb-4">
            <p className="text-sm text-gray-500">{appealsTotal} {appealsStatus} appeals</p>
            <select className="input w-auto text-sm" value={appealsStatus} onChange={(e) => setAppealsStatus(e.target.value)}>
              <option value="pending">Pending</option>
              <option value="approved">Approved</option>
              <option value="rejected">Rejected</option>
            </select>
          </div>

          {appealsLoading ? (
            <div className="space-y-4">
              {[...Array(3)].map((_, i) => <div key={i} className="card p-6 animate-pulse"><div className="h-24 bg-warm-300 rounded" /></div>)}
            </div>
          ) : appeals.length === 0 ? (
            <div className="card p-12 text-center">
              <Scale className="w-12 h-12 text-green-400 mx-auto mb-3" />
              <p className="text-gray-500 font-medium">No {appealsStatus} appeals</p>
            </div>
          ) : (
            <div className="space-y-4">
              {appeals.map((appeal) => (
                <div key={appeal.id} className="card p-5">
                  <div className="flex items-center gap-2 mb-3">
                    <span className={`badge ${statusColor(appeal.status)}`}>{appeal.status}</span>
                    <span className="badge bg-orange-50 text-orange-700">{appeal.violation_type}</span>
                    <span className="text-xs text-gray-400 flex items-center gap-1"><Clock className="w-3 h-3" />{formatDateTime(appeal.created_at)}</span>
                  </div>

                  <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                    <div>
                      <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Violation</h4>
                      <div className="bg-red-50 rounded-lg p-3 mb-3">
                        <p className="text-sm font-medium text-red-800">{appeal.violation_reason}</p>
                        {appeal.flag_reason && <p className="text-xs text-red-600 mt-1">Flag: {appeal.flag_reason}</p>}
                        <p className="text-xs text-red-500 mt-1">Severity: {(appeal.severity_score * 100).toFixed(0)}%</p>
                      </div>

                      {(appeal.post_body || appeal.comment_body) && (
                        <div>
                          <h4 className="text-xs font-semibold text-gray-500 uppercase mb-1">Original Content</h4>
                          <div className="bg-warm-100 rounded-lg p-3">
                            <p className="text-sm text-gray-700 whitespace-pre-wrap">{appeal.post_body || appeal.comment_body}</p>
                          </div>
                        </div>
                      )}
                    </div>

                    <div>
                      <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Appeal by @{appeal.user?.handle || '—'}</h4>
                      <div className="bg-blue-50 rounded-lg p-3 mb-3">
                        <p className="text-sm text-blue-900 font-medium mb-1">Reason:</p>
                        <p className="text-sm text-blue-800">{appeal.appeal_reason}</p>
                        {appeal.appeal_context && (
                          <>
                            <p className="text-sm text-blue-900 font-medium mt-2 mb-1">Context:</p>
                            <p className="text-sm text-blue-800">{appeal.appeal_context}</p>
                          </>
                        )}
                      </div>

                      {/* Contextual user info */}
                      <UserContextPanel userId={appeal.user_id} handle={appeal.user?.handle} />

                      {appeal.flag_scores && (
                        <div className="text-xs text-gray-500 space-y-1 mt-3">
                          {Object.entries(appeal.flag_scores).map(([key, value]) => (
                            <div key={key} className="flex items-center gap-2">
                              <span className="w-16">{key}</span>
                              <div className="flex-1 h-1.5 bg-warm-300 rounded-full overflow-hidden">
                                <div className={`h-full rounded-full ${(value as number) > 0.7 ? 'bg-red-500' : (value as number) > 0.4 ? 'bg-yellow-500' : 'bg-green-500'}`}
                                  style={{ width: `${(value as number) * 100}%` }} />
                              </div>
                              <span className="w-8 text-right font-mono">{((value as number) * 100).toFixed(0)}%</span>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>

                  {appeal.status === 'pending' && (
                    <>
                      {appealReviewId === appeal.id ? (
                        <div className="mt-4 p-4 bg-warm-100 border border-warm-400 rounded-lg">
                          <p className="text-sm font-medium text-gray-700 mb-2">Write your review decision:</p>
                          <textarea className="input mb-3" rows={3} placeholder="Explain your decision (min 5 chars)..."
                            value={appealDecision} onChange={(e) => setAppealDecision(e.target.value)} />
                          <label className="flex items-center gap-2 text-sm text-gray-600 mb-3">
                            <input type="checkbox" checked={restoreContent} onChange={(e) => setRestoreContent(e.target.checked)} className="rounded" />
                            Restore original content (if approving)
                          </label>
                          <div className="flex gap-2">
                            <button onClick={() => { setAppealReviewId(null); setAppealDecision(''); }} className="btn-secondary text-sm">Cancel</button>
                            <button onClick={() => handleAppealReview(appeal.id, 'approved')}
                              className="bg-green-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-green-700 flex items-center gap-1"
                              disabled={appealDecision.trim().length < 5}>
                              <CheckCircle className="w-4 h-4" /> Approve Appeal
                            </button>
                            <button onClick={() => handleAppealReview(appeal.id, 'rejected')}
                              className="btn-danger text-sm flex items-center gap-1"
                              disabled={appealDecision.trim().length < 5}>
                              <XCircle className="w-4 h-4" /> Reject Appeal
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="mt-4 flex gap-2">
                          <button onClick={() => setAppealReviewId(appeal.id)} className="btn-primary text-sm flex items-center gap-1">
                            <Scale className="w-4 h-4" /> Review This Appeal
                          </button>
                        </div>
                      )}
                    </>
                  )}

                  {appeal.review_decision && (
                    <div className="mt-4 p-3 bg-warm-100 rounded-lg">
                      <p className="text-xs font-semibold text-gray-500 uppercase mb-1">Review Decision</p>
                      <p className="text-sm text-gray-700">{appeal.review_decision}</p>
                      {appeal.reviewed_at && <p className="text-xs text-gray-400 mt-1">Reviewed {formatDateTime(appeal.reviewed_at)}</p>}
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ═══ REPORTS TAB ═══ */}
      {tab === 'reports' && (
        <div>
          <div className="flex items-center justify-between mb-4">
            <p className="text-sm text-gray-500">{reportsTotal} {reportsStatus} reports</p>
            <select className="input w-auto text-sm" value={reportsStatus} onChange={(e) => { setReportsStatus(e.target.value); setReportsSelected(new Set()); }}>
              <option value="pending">Pending</option>
              <option value="reviewed">Reviewed</option>
              <option value="actioned">Actioned</option>
              <option value="dismissed">Dismissed</option>
            </select>
          </div>

          {reportsStatus === 'pending' && (
            <SelectionBar
              count={reportsSelected.size}
              total={reports.length}
              onSelectAll={() => setReportsSelected(new Set(reports.map((r) => r.id)))}
              onClearSelection={() => setReportsSelected(new Set())}
              loading={reportsBulkLoading}
              actions={[
                { label: 'Action All', action: 'actioned', color: 'bg-green-50 text-green-700 hover:bg-green-100', icon: <CheckCircle className="w-3.5 h-3.5" /> },
                { label: 'Dismiss All', action: 'dismissed', color: 'bg-gray-100 text-gray-700 hover:bg-gray-200', icon: <XCircle className="w-3.5 h-3.5" /> },
              ]}
              onAction={handleReportsBulk}
            />
          )}

          {reportsLoading ? (
            <div className="space-y-4">
              {[...Array(3)].map((_, i) => <div key={i} className="card p-6 animate-pulse"><div className="h-16 bg-warm-300 rounded" /></div>)}
            </div>
          ) : reports.length === 0 ? (
            <div className="card p-12 text-center">
              <Flag className="w-12 h-12 text-green-400 mx-auto mb-3" />
              <p className="text-gray-500 font-medium">No {reportsStatus} reports</p>
            </div>
          ) : (
            <div className="card overflow-hidden">
              <table className="w-full">
                <thead className="bg-warm-200">
                  <tr>
                    {reportsStatus === 'pending' && (
                      <th className="table-header w-10">
                        <input type="checkbox" className="rounded border-gray-300"
                          checked={reports.length > 0 && reportsSelected.size === reports.length}
                          onChange={() => {
                            if (reportsSelected.size === reports.length) setReportsSelected(new Set());
                            else setReportsSelected(new Set(reports.map((r) => r.id)));
                          }} />
                      </th>
                    )}
                    <th className="table-header">Reporter</th>
                    <th className="table-header">Target</th>
                    <th className="table-header">Type</th>
                    <th className="table-header">Description</th>
                    <th className="table-header">Content</th>
                    <th className="table-header">Status</th>
                    <th className="table-header">Date</th>
                    <th className="table-header">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-warm-300">
                  {reports.map((report) => (
                    <tr key={report.id} className={`hover:bg-warm-50 transition-colors ${reportsSelected.has(report.id) ? 'bg-brand-50' : ''}`}>
                      {reportsStatus === 'pending' && (
                        <td className="table-cell">
                          <input type="checkbox" className="rounded border-gray-300" checked={reportsSelected.has(report.id)}
                            onChange={() => setReportsSelected((prev) => { const s = new Set(prev); s.has(report.id) ? s.delete(report.id) : s.add(report.id); return s; })} />
                        </td>
                      )}
                      <td className="table-cell">
                        <Link href={`/users/${report.reporter_id}`} className="text-brand-500 hover:text-brand-700 text-sm">
                          @{report.reporter_handle || '—'}
                        </Link>
                      </td>
                      <td className="table-cell">
                        <Link href={`/users/${report.target_user_id}`} className="text-brand-500 hover:text-brand-700 text-sm">
                          @{report.target_handle || '—'}
                        </Link>
                      </td>
                      <td className="table-cell">
                        <span className="badge bg-orange-50 text-orange-700">
                          <AlertTriangle className="w-3 h-3 mr-1" />{report.violation_type}
                        </span>
                      </td>
                      <td className="table-cell max-w-xs">
                        <p className="text-sm text-gray-700 line-clamp-2">{report.description}</p>
                      </td>
                      <td className="table-cell text-xs text-gray-500">
                        {report.post_id && <Link href={`/posts/${report.post_id}`} className="text-brand-500 hover:text-brand-700">View Post</Link>}
                      </td>
                      <td className="table-cell">
                        <span className={`badge ${statusColor(report.status)}`}>{report.status}</span>
                      </td>
                      <td className="table-cell text-xs text-gray-500">{formatDateTime(report.created_at)}</td>
                      <td className="table-cell">
                        {report.status === 'pending' && (
                          <div className="flex gap-1">
                            <button onClick={() => handleReportUpdate(report.id, 'actioned')}
                              className="p-1.5 bg-green-50 text-green-700 rounded hover:bg-green-100" title="Action taken">
                              <CheckCircle className="w-4 h-4" />
                            </button>
                            <button onClick={() => handleReportUpdate(report.id, 'dismissed')}
                              className="p-1.5 bg-gray-50 text-gray-600 rounded hover:bg-gray-100" title="Dismiss">
                              <XCircle className="w-4 h-4" />
                            </button>
                          </div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </AdminShell>
  );
}
