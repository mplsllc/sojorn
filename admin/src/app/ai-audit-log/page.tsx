'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { formatDateTime } from '@/lib/utils';
import { useEffect, useState, useCallback } from 'react';
import {
  ScrollText, Search, ThumbsUp, ThumbsDown, Download,
  ChevronLeft, ChevronRight, Filter, MessageSquare, FileText,
  CheckCircle, XCircle, AlertTriangle, Eye,
} from 'lucide-react';

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

function DecisionBadge({ decision }: { decision: string }) {
  const styles: Record<string, string> = {
    pass: 'bg-green-50 text-green-700 border-green-200',
    flag: 'bg-red-50 text-red-700 border-red-200',
    nsfw: 'bg-amber-50 text-amber-700 border-amber-200',
  };
  const icons: Record<string, React.ReactNode> = {
    pass: <CheckCircle className="w-3 h-3" />,
    flag: <AlertTriangle className="w-3 h-3" />,
    nsfw: <Eye className="w-3 h-3" />,
  };
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium border ${styles[decision] || 'bg-gray-50 text-gray-600 border-gray-200'}`}>
      {icons[decision]} {decision.toUpperCase()}
    </span>
  );
}

function FeedbackBadge({ correct }: { correct: boolean | null }) {
  if (correct === null || correct === undefined) {
    return <span className="text-xs text-gray-400 italic">Not reviewed</span>;
  }
  return correct ? (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-green-50 text-green-700 border border-green-200">
      <ThumbsUp className="w-3 h-3" /> Correct
    </span>
  ) : (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-red-50 text-red-700 border border-red-200">
      <ThumbsDown className="w-3 h-3" /> Incorrect
    </span>
  );
}

export default function AIAuditLogPage() {
  const [items, setItems] = useState<any[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(0);
  const limit = 25;

  // Filters
  const [decisionFilter, setDecisionFilter] = useState('');
  const [contentTypeFilter, setContentTypeFilter] = useState('');
  const [feedbackFilter, setFeedbackFilter] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [searchInput, setSearchInput] = useState('');

  // Feedback modal
  const [feedbackId, setFeedbackId] = useState<string | null>(null);
  const [feedbackCorrect, setFeedbackCorrect] = useState<boolean | null>(null);
  const [feedbackReason, setFeedbackReason] = useState('');
  const [submitting, setSubmitting] = useState(false);

  // Expanded row
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const fetchLog = useCallback(() => {
    setLoading(true);
    api.getAIModerationLog({
      limit,
      offset: page * limit,
      decision: decisionFilter || undefined,
      content_type: contentTypeFilter || undefined,
      search: searchQuery || undefined,
      feedback: feedbackFilter || undefined,
    })
      .then((data) => {
        setItems(data.items || []);
        setTotal(data.total || 0);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [page, decisionFilter, contentTypeFilter, feedbackFilter, searchQuery]);

  useEffect(() => { fetchLog(); }, [fetchLog]);

  const handleSearch = () => {
    setPage(0);
    setSearchQuery(searchInput);
  };

  const handleFeedbackSubmit = async () => {
    if (!feedbackId || feedbackCorrect === null || !feedbackReason.trim()) return;
    setSubmitting(true);
    try {
      await api.submitAIModerationFeedback(feedbackId, feedbackCorrect, feedbackReason);
      setFeedbackId(null);
      setFeedbackCorrect(null);
      setFeedbackReason('');
      fetchLog();
    } catch (e: any) {
      alert(`Failed: ${e.message}`);
    }
    setSubmitting(false);
  };

  const handleExport = async () => {
    try {
      const data = await api.exportAITrainingData();
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `ai-training-data-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e: any) {
      alert(`Export failed: ${e.message}`);
    }
  };

  const totalPages = Math.ceil(total / limit);

  const feedbackPresets = [
    'AI correctly identified harmful content',
    'AI correctly passed safe content',
    'False positive — content was actually fine',
    'False negative — content should have been flagged',
    'AI flagged satire/humor incorrectly',
    'Threshold too sensitive for this type of content',
    'AI missed context — cultural/religious reference',
  ];

  return (
    <AdminShell>
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <ScrollText className="w-6 h-6 text-brand-500" />
            AI Moderation Audit Log
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            {total} decisions logged &middot; Review AI decisions and provide training feedback
          </p>
        </div>
        <button
          onClick={handleExport}
          className="flex items-center gap-2 px-4 py-2 bg-brand-50 text-brand-700 rounded-lg text-sm font-medium hover:bg-brand-100 transition-colors"
        >
          <Download className="w-4 h-4" /> Export Training Data
        </button>
      </div>

      {/* Filters */}
      <div className="card p-4 mb-6">
        <div className="flex flex-wrap items-center gap-3">
          <Filter className="w-4 h-4 text-gray-400" />

          {/* Search */}
          <div className="flex items-center gap-1">
            <input
              className="input w-48 text-sm"
              placeholder="Search content or @handle..."
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
            />
            <button onClick={handleSearch} className="p-2 bg-warm-200 rounded-lg hover:bg-warm-300 transition-colors">
              <Search className="w-4 h-4 text-gray-600" />
            </button>
          </div>

          {/* Decision filter */}
          <select
            className="input w-auto text-sm"
            value={decisionFilter}
            onChange={(e) => { setDecisionFilter(e.target.value); setPage(0); }}
          >
            <option value="">All Decisions</option>
            <option value="pass">Pass</option>
            <option value="flag">Flag</option>
            <option value="nsfw">NSFW</option>
          </select>

          {/* Content type filter */}
          <select
            className="input w-auto text-sm"
            value={contentTypeFilter}
            onChange={(e) => { setContentTypeFilter(e.target.value); setPage(0); }}
          >
            <option value="">All Types</option>
            <option value="post">Posts</option>
            <option value="comment">Comments</option>
          </select>

          {/* Feedback filter */}
          <select
            className="input w-auto text-sm"
            value={feedbackFilter}
            onChange={(e) => { setFeedbackFilter(e.target.value); setPage(0); }}
          >
            <option value="">All Feedback</option>
            <option value="reviewed">Reviewed</option>
            <option value="unreviewed">Not Reviewed</option>
          </select>

          {(decisionFilter || contentTypeFilter || feedbackFilter || searchQuery) && (
            <button
              onClick={() => { setDecisionFilter(''); setContentTypeFilter(''); setFeedbackFilter(''); setSearchQuery(''); setSearchInput(''); setPage(0); }}
              className="text-xs text-brand-600 hover:text-brand-700 font-medium"
            >
              Clear filters
            </button>
          )}
        </div>
      </div>

      {/* Table */}
      {loading ? (
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="card p-5 animate-pulse">
              <div className="h-16 bg-warm-300 rounded" />
            </div>
          ))}
        </div>
      ) : items.length === 0 ? (
        <div className="card p-12 text-center">
          <ScrollText className="w-12 h-12 text-gray-300 mx-auto mb-3" />
          <p className="text-gray-500 font-medium">No audit log entries found</p>
          <p className="text-sm text-gray-400 mt-1">AI moderation decisions will appear here as content is created.</p>
        </div>
      ) : (
        <>
          <div className="space-y-3">
            {items.map((item) => (
              <div key={item.id} className="card overflow-hidden">
                {/* Main row */}
                <div
                  className="p-4 cursor-pointer hover:bg-warm-50 transition-colors"
                  onClick={() => setExpandedId(expandedId === item.id ? null : item.id)}
                >
                  <div className="flex items-start justify-between gap-4">
                    <div className="flex-1 min-w-0">
                      {/* Top badges */}
                      <div className="flex items-center gap-2 mb-2 flex-wrap">
                        <DecisionBadge decision={item.decision} />
                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600 border border-gray-200">
                          {item.content_type === 'post' ? <FileText className="w-3 h-3" /> : <MessageSquare className="w-3 h-3" />}
                          {item.content_type}
                        </span>
                        {item.flag_reason && (
                          <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-orange-50 text-orange-700 border border-orange-200">
                            {item.flag_reason}
                          </span>
                        )}
                        <span className="text-xs text-gray-400 ml-auto flex-shrink-0">
                          {formatDateTime(item.created_at)}
                        </span>
                      </div>

                      {/* Content snippet */}
                      <p className="text-sm text-gray-700 line-clamp-2 mb-1">
                        {item.content_snippet || <span className="italic text-gray-400">No content</span>}
                      </p>

                      {/* Author */}
                      <p className="text-xs text-gray-500">
                        By <span className="font-medium text-gray-700">@{item.author_handle || '—'}</span>
                        {item.author_display_name && ` (${item.author_display_name})`}
                      </p>
                    </div>

                    {/* Right side: scores + feedback status */}
                    <div className="flex flex-col items-end gap-2 flex-shrink-0">
                      <div className="w-40 space-y-1">
                        <ScoreBar label="Hate" value={item.scores_hate || 0} />
                        <ScoreBar label="Greed" value={item.scores_greed || 0} />
                        <ScoreBar label="Delusion" value={item.scores_delusion || 0} />
                      </div>
                      <div className="mt-1">
                        <FeedbackBadge correct={item.feedback_correct} />
                      </div>
                    </div>
                  </div>
                </div>

                {/* Expanded detail */}
                {expandedId === item.id && (
                  <div className="border-t border-warm-300 bg-warm-50 p-4">
                    <div className="grid grid-cols-2 gap-4 mb-4">
                      <div>
                        <h4 className="text-xs font-semibold text-gray-500 uppercase mb-1">Content ID</h4>
                        <p className="text-xs font-mono text-gray-600 break-all">{item.content_id}</p>
                      </div>
                      <div>
                        <h4 className="text-xs font-semibold text-gray-500 uppercase mb-1">AI Provider</h4>
                        <p className="text-xs text-gray-600">{item.ai_provider || 'openai'}</p>
                      </div>
                      {item.or_decision && (
                        <div>
                          <h4 className="text-xs font-semibold text-gray-500 uppercase mb-1">OpenRouter Decision</h4>
                          <p className="text-xs text-gray-600">{item.or_decision}</p>
                        </div>
                      )}
                      {item.feedback_reason && (
                        <div className="col-span-2">
                          <h4 className="text-xs font-semibold text-gray-500 uppercase mb-1">Admin Feedback</h4>
                          <p className="text-sm text-gray-700 bg-white rounded-lg p-3 border border-warm-300">{item.feedback_reason}</p>
                          {item.feedback_at && (
                            <p className="text-xs text-gray-400 mt-1">Reviewed {formatDateTime(item.feedback_at)}</p>
                          )}
                        </div>
                      )}
                    </div>

                    {/* Feedback form */}
                    {item.feedback_correct === null || item.feedback_correct === undefined ? (
                      feedbackId === item.id ? (
                        <div className="bg-white rounded-lg border border-warm-300 p-4">
                          <h4 className="text-sm font-semibold text-gray-800 mb-3">Train the AI — Was this decision correct?</h4>

                          {/* Correct / Incorrect toggle */}
                          <div className="flex gap-2 mb-3">
                            <button
                              onClick={() => setFeedbackCorrect(true)}
                              className={`flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                                feedbackCorrect === true
                                  ? 'bg-green-100 text-green-800 ring-2 ring-green-400'
                                  : 'bg-warm-100 text-gray-600 hover:bg-warm-200'
                              }`}
                            >
                              <ThumbsUp className="w-4 h-4" /> Correct
                            </button>
                            <button
                              onClick={() => setFeedbackCorrect(false)}
                              className={`flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                                feedbackCorrect === false
                                  ? 'bg-red-100 text-red-800 ring-2 ring-red-400'
                                  : 'bg-warm-100 text-gray-600 hover:bg-warm-200'
                              }`}
                            >
                              <ThumbsDown className="w-4 h-4" /> Incorrect
                            </button>
                          </div>

                          {/* Preset reasons */}
                          <div className="space-y-1 mb-3">
                            {feedbackPresets
                              .filter(p => {
                                if (feedbackCorrect === true) return p.startsWith('AI correctly');
                                if (feedbackCorrect === false) return !p.startsWith('AI correctly');
                                return true;
                              })
                              .map((preset) => (
                              <button
                                key={preset}
                                onClick={() => setFeedbackReason(preset)}
                                className={`w-full text-left px-3 py-1.5 rounded text-xs border transition-colors ${
                                  feedbackReason === preset
                                    ? 'border-brand-400 bg-brand-50 text-brand-800 font-medium'
                                    : 'border-warm-300 hover:border-warm-400 text-gray-700'
                                }`}
                              >
                                {preset}
                              </button>
                            ))}
                          </div>

                          {/* Custom reason */}
                          <textarea
                            className="input w-full text-sm mb-3"
                            rows={2}
                            placeholder="Or write a custom explanation for fine-tuning..."
                            value={feedbackReason}
                            onChange={(e) => setFeedbackReason(e.target.value)}
                          />

                          <div className="flex gap-2">
                            <button
                              onClick={() => { setFeedbackId(null); setFeedbackCorrect(null); setFeedbackReason(''); }}
                              className="btn-secondary text-xs"
                            >
                              Cancel
                            </button>
                            <button
                              onClick={handleFeedbackSubmit}
                              disabled={feedbackCorrect === null || !feedbackReason.trim() || submitting}
                              className="btn-primary text-xs disabled:opacity-50"
                            >
                              {submitting ? 'Saving...' : 'Submit Feedback'}
                            </button>
                          </div>
                        </div>
                      ) : (
                        <button
                          onClick={() => setFeedbackId(item.id)}
                          className="flex items-center gap-2 px-4 py-2 bg-brand-50 text-brand-700 rounded-lg text-sm font-medium hover:bg-brand-100 transition-colors"
                        >
                          <ScrollText className="w-4 h-4" /> Provide Training Feedback
                        </button>
                      )
                    ) : (
                      <div className="text-xs text-gray-400 italic flex items-center gap-1">
                        <CheckCircle className="w-3.5 h-3.5 text-green-500" />
                        Feedback already submitted
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-between mt-6">
              <p className="text-sm text-gray-500">
                Showing {page * limit + 1}–{Math.min((page + 1) * limit, total)} of {total}
              </p>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setPage(Math.max(0, page - 1))}
                  disabled={page === 0}
                  className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-sm font-medium bg-warm-100 hover:bg-warm-200 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                >
                  <ChevronLeft className="w-4 h-4" /> Prev
                </button>
                <span className="text-sm text-gray-600 font-medium">
                  Page {page + 1} of {totalPages}
                </span>
                <button
                  onClick={() => setPage(Math.min(totalPages - 1, page + 1))}
                  disabled={page >= totalPages - 1}
                  className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-sm font-medium bg-warm-100 hover:bg-warm-200 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                >
                  Next <ChevronRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          )}
        </>
      )}
    </AdminShell>
  );
}
