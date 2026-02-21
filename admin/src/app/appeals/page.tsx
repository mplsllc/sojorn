// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { statusColor, formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Scale, CheckCircle, XCircle, RotateCcw } from 'lucide-react';

export default function AppealsPage() {
  const [appeals, setAppeals] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('pending');
  const [reviewingId, setReviewingId] = useState<string | null>(null);
  const [reviewDecision, setReviewDecision] = useState('');
  const [restoreContent, setRestoreContent] = useState(false);

  const fetchAppeals = () => {
    setLoading(true);
    api.listAppeals({ limit: 50, status: statusFilter })
      .then((data) => { setAppeals(data.appeals); setTotal(data.total); })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchAppeals(); }, [statusFilter]);

  const handleReview = async (id: string, decision: 'approved' | 'rejected') => {
    if (!reviewDecision.trim()) return;
    try {
      await api.reviewAppeal(id, decision, reviewDecision, restoreContent);
      setReviewingId(null);
      setReviewDecision('');
      setRestoreContent(false);
      fetchAppeals();
    } catch {}
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Appeals</h1>
          <p className="text-sm text-gray-500 mt-1">{total} {statusFilter} appeals</p>
        </div>
        <select className="input w-auto" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="pending">Pending</option>
          <option value="approved">Approved</option>
          <option value="rejected">Rejected</option>
        </select>
      </div>

      {loading ? (
        <div className="space-y-4">
          {[...Array(3)].map((_, i) => <div key={i} className="card p-6 animate-pulse"><div className="h-24 bg-warm-300 rounded" /></div>)}
        </div>
      ) : appeals.length === 0 ? (
        <div className="card p-12 text-center">
          <Scale className="w-12 h-12 text-green-400 mx-auto mb-3" />
          <p className="text-gray-500 font-medium">No {statusFilter} appeals</p>
        </div>
      ) : (
        <div className="space-y-4">
          {appeals.map((appeal) => (
            <div key={appeal.id} className="card p-5">
              {/* Header */}
              <div className="flex items-center gap-2 mb-3">
                <span className={`badge ${statusColor(appeal.status)}`}>{appeal.status}</span>
                <span className="badge bg-orange-50 text-orange-700">{appeal.violation_type}</span>
                <span className="text-xs text-gray-400">{formatDateTime(appeal.created_at)}</span>
              </div>

              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                {/* Violation Info */}
                <div>
                  <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Violation</h4>
                  <div className="bg-red-50 rounded-lg p-3 mb-3">
                    <p className="text-sm font-medium text-red-800">{appeal.violation_reason}</p>
                    {appeal.flag_reason && <p className="text-xs text-red-600 mt-1">Flag: {appeal.flag_reason}</p>}
                    <p className="text-xs text-red-500 mt-1">Severity: {(appeal.severity_score * 100).toFixed(0)}%</p>
                  </div>

                  {/* Original Content */}
                  {(appeal.post_body || appeal.comment_body) && (
                    <div>
                      <h4 className="text-xs font-semibold text-gray-500 uppercase mb-1">Original Content</h4>
                      <div className="bg-warm-100 rounded-lg p-3">
                        <p className="text-sm text-gray-700 whitespace-pre-wrap">{appeal.post_body || appeal.comment_body}</p>
                      </div>
                    </div>
                  )}
                </div>

                {/* Appeal Info */}
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

                  {/* AI Scores */}
                  {appeal.flag_scores && (
                    <div className="text-xs text-gray-500 space-y-1">
                      {Object.entries(appeal.flag_scores).map(([key, value]) => (
                        <div key={key} className="flex items-center gap-2">
                          <span className="w-16">{key}</span>
                          <div className="flex-1 h-1.5 bg-warm-300 rounded-full overflow-hidden">
                            <div
                              className={`h-full rounded-full ${(value as number) > 0.7 ? 'bg-red-500' : (value as number) > 0.4 ? 'bg-yellow-500' : 'bg-green-500'}`}
                              style={{ width: `${(value as number) * 100}%` }}
                            />
                          </div>
                          <span className="w-8 text-right font-mono">{((value as number) * 100).toFixed(0)}%</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              {/* Review Actions */}
              {appeal.status === 'pending' && (
                <>
                  {reviewingId === appeal.id ? (
                    <div className="mt-4 p-4 bg-warm-100 border border-warm-400 rounded-lg">
                      <p className="text-sm font-medium text-gray-700 mb-2">Write your review decision:</p>
                      <textarea
                        className="input mb-3"
                        rows={3}
                        placeholder="Explain your decision (min 5 chars)..."
                        value={reviewDecision}
                        onChange={(e) => setReviewDecision(e.target.value)}
                      />
                      <label className="flex items-center gap-2 text-sm text-gray-600 mb-3">
                        <input type="checkbox" checked={restoreContent} onChange={(e) => setRestoreContent(e.target.checked)} className="rounded" />
                        Restore original content (if approving)
                      </label>
                      <div className="flex gap-2">
                        <button onClick={() => { setReviewingId(null); setReviewDecision(''); }} className="btn-secondary text-sm">Cancel</button>
                        <button
                          onClick={() => handleReview(appeal.id, 'approved')}
                          className="bg-green-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-green-700 flex items-center gap-1"
                          disabled={reviewDecision.trim().length < 5}
                        >
                          <CheckCircle className="w-4 h-4" /> Approve Appeal
                        </button>
                        <button
                          onClick={() => handleReview(appeal.id, 'rejected')}
                          className="btn-danger text-sm flex items-center gap-1"
                          disabled={reviewDecision.trim().length < 5}
                        >
                          <XCircle className="w-4 h-4" /> Reject Appeal
                        </button>
                      </div>
                    </div>
                  ) : (
                    <div className="mt-4 flex gap-2">
                      <button onClick={() => setReviewingId(appeal.id)} className="btn-primary text-sm flex items-center gap-1">
                        <Scale className="w-4 h-4" /> Review This Appeal
                      </button>
                    </div>
                  )}
                </>
              )}

              {/* Already reviewed */}
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
    </AdminShell>
  );
}
