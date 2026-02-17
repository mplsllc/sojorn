'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import { Sliders, Save, RefreshCw, BarChart2 } from 'lucide-react';

export default function AlgorithmPage() {
  const [configs, setConfigs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [editValues, setEditValues] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState<string | null>(null);
  const [scores, setScores] = useState<any[]>([]);
  const [scoresLoading, setScoresLoading] = useState(false);
  const [showScores, setShowScores] = useState(false);

  const fetchConfig = () => {
    setLoading(true);
    api.getAlgorithmConfig()
      .then((data) => {
        setConfigs(data.config || []);
        const vals: Record<string, string> = {};
        (data.config || []).forEach((c: any) => { vals[c.key] = c.value; });
        setEditValues(vals);
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchConfig(); }, []);

  const handleSave = async (key: string) => {
    setSaving(key);
    try {
      await api.updateAlgorithmConfig(key, editValues[key]);
      fetchConfig();
    } catch {}
    setSaving(null);
  };

  const loadScores = () => {
    setScoresLoading(true);
    setShowScores(true);
    api.getFeedScores()
      .then((data) => setScores(data.scores ?? []))
      .catch(() => {})
      .finally(() => setScoresLoading(false));
  };

  const groupedConfigs = {
    feed: configs.filter((c) => c.key.startsWith('feed_')),
    moderation: configs.filter((c) => c.key.startsWith('moderation_')),
    other: configs.filter((c) => !c.key.startsWith('feed_') && !c.key.startsWith('moderation_')),
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Algorithm & Feed Settings</h1>
          <p className="text-sm text-gray-500 mt-1">Configure feed ranking weights and moderation thresholds</p>
        </div>
        <button onClick={fetchConfig} className="btn-secondary text-sm flex items-center gap-1">
          <RefreshCw className="w-4 h-4" /> Refresh
        </button>
      </div>

      {loading ? (
        <div className="card p-8 animate-pulse"><div className="h-40 bg-warm-300 rounded" /></div>
      ) : (
        <div className="space-y-6">
          {/* Feed Settings */}
          <div className="card p-5">
            <div className="flex items-center gap-2 mb-4">
              <Sliders className="w-5 h-5 text-brand-500" />
              <h3 className="text-lg font-semibold text-gray-900">Feed Ranking Weights</h3>
            </div>
            <p className="text-sm text-gray-500 mb-4">
              These weights control how posts are ranked in users&apos; feeds. Values should be between 0 and 1 and ideally sum to 1.0.
            </p>
            <div className="space-y-4">
              {groupedConfigs.feed.map((config) => (
                <div key={config.key} className="flex items-center gap-4">
                  <div className="flex-1">
                    <label className="text-sm font-medium text-gray-700">{config.key.replace('feed_', '').replace(/_/g, ' ').replace(/\b\w/g, (l: string) => l.toUpperCase())}</label>
                    <p className="text-xs text-gray-400">{config.description || config.key}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      type="text"
                      className="input w-24 text-center text-sm"
                      value={editValues[config.key] || ''}
                      onChange={(e) => setEditValues({ ...editValues, [config.key]: e.target.value })}
                    />
                    <button
                      onClick={() => handleSave(config.key)}
                      className="btn-primary text-xs py-2 px-3"
                      disabled={saving === config.key || editValues[config.key] === config.value}
                    >
                      {saving === config.key ? '...' : <Save className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                </div>
              ))}
              {groupedConfigs.feed.length === 0 && (
                <p className="text-sm text-gray-400 italic">No feed settings configured yet. They will appear once the algorithm_config table is populated.</p>
              )}
            </div>
          </div>

          {/* Moderation Settings */}
          <div className="card p-5">
            <div className="flex items-center gap-2 mb-4">
              <Sliders className="w-5 h-5 text-red-500" />
              <h3 className="text-lg font-semibold text-gray-900">AI Moderation Thresholds</h3>
            </div>
            <p className="text-sm text-gray-500 mb-4">
              Control the sensitivity of the AI moderation system. Lower thresholds = more aggressive flagging.
            </p>
            <div className="space-y-4">
              {groupedConfigs.moderation.map((config) => (
                <div key={config.key} className="flex items-center gap-4">
                  <div className="flex-1">
                    <label className="text-sm font-medium text-gray-700">{config.key.replace('moderation_', '').replace(/_/g, ' ').replace(/\b\w/g, (l: string) => l.toUpperCase())}</label>
                    <p className="text-xs text-gray-400">{config.description || config.key}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <input
                      type="text"
                      className="input w-24 text-center text-sm"
                      value={editValues[config.key] || ''}
                      onChange={(e) => setEditValues({ ...editValues, [config.key]: e.target.value })}
                    />
                    <button
                      onClick={() => handleSave(config.key)}
                      className="btn-primary text-xs py-2 px-3"
                      disabled={saving === config.key || editValues[config.key] === config.value}
                    >
                      {saving === config.key ? '...' : <Save className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                </div>
              ))}
              {groupedConfigs.moderation.length === 0 && (
                <p className="text-sm text-gray-400 italic">No moderation thresholds configured yet.</p>
              )}
            </div>
          </div>

          {/* Other */}
          {groupedConfigs.other.length > 0 && (
            <div className="card p-5">
              <h3 className="text-lg font-semibold text-gray-900 mb-4">Other Settings</h3>
              <div className="space-y-4">
                {groupedConfigs.other.map((config) => (
                  <div key={config.key} className="flex items-center gap-4">
                    <div className="flex-1">
                      <label className="text-sm font-medium text-gray-700">{config.key}</label>
                      <p className="text-xs text-gray-400">{config.description}</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <input
                        type="text"
                        className="input w-24 text-center text-sm"
                        value={editValues[config.key] || ''}
                        onChange={(e) => setEditValues({ ...editValues, [config.key]: e.target.value })}
                      />
                      <button
                        onClick={() => handleSave(config.key)}
                        className="btn-primary text-xs py-2 px-3"
                        disabled={saving === config.key || editValues[config.key] === config.value}
                      >
                        {saving === config.key ? '...' : <Save className="w-3.5 h-3.5" />}
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Feed Scores Viewer */}
      <div className="mt-8">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <BarChart2 className="w-5 h-5 text-gray-600" />
            <h2 className="text-lg font-semibold text-gray-800">Live Feed Scores</h2>
          </div>
          <button
            onClick={loadScores}
            className="flex items-center gap-1.5 px-3 py-1.5 border rounded-lg text-sm hover:bg-gray-50"
          >
            <RefreshCw className={`w-4 h-4 ${scoresLoading ? 'animate-spin' : ''}`} />
            {showScores ? 'Refresh' : 'Load Scores'}
          </button>
        </div>
        {showScores && (
          <div className="bg-white rounded-xl border overflow-hidden">
            {scoresLoading ? (
              <div className="p-6 text-center text-gray-400">Loading scores…</div>
            ) : scores.length === 0 ? (
              <div className="p-6 text-center text-gray-400">No scored posts yet</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-gray-50 border-b">
                    <tr>
                      <th className="px-4 py-3 text-left font-medium text-gray-600">Post</th>
                      <th className="px-4 py-3 text-right font-medium text-gray-600">Total</th>
                      <th className="px-4 py-3 text-right font-medium text-gray-600">Engage</th>
                      <th className="px-4 py-3 text-right font-medium text-gray-600">Quality</th>
                      <th className="px-4 py-3 text-right font-medium text-gray-600">Recency</th>
                      <th className="px-4 py-3 text-right font-medium text-gray-600">Network</th>
                      <th className="px-4 py-3 text-right font-medium text-gray-600">Personal</th>
                      <th className="px-4 py-3 text-left font-medium text-gray-600">Updated</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {scores.map((s) => (
                      <tr key={s.post_id} className="hover:bg-gray-50">
                        <td className="px-4 py-2.5 max-w-xs">
                          <p className="truncate text-gray-800" title={s.excerpt}>{s.excerpt || '—'}</p>
                          <p className="text-xs text-gray-400 font-mono">{s.post_id.slice(0, 8)}…</p>
                        </td>
                        <td className="px-4 py-2.5 text-right font-semibold text-blue-700">
                          {Number(s.total_score).toFixed(2)}
                        </td>
                        <td className="px-4 py-2.5 text-right text-gray-600">{Number(s.engagement_score).toFixed(2)}</td>
                        <td className="px-4 py-2.5 text-right text-gray-600">{Number(s.quality_score).toFixed(2)}</td>
                        <td className="px-4 py-2.5 text-right text-gray-600">{Number(s.recency_score).toFixed(2)}</td>
                        <td className="px-4 py-2.5 text-right text-gray-600">{Number(s.network_score).toFixed(2)}</td>
                        <td className="px-4 py-2.5 text-right text-gray-600">{Number(s.personalization).toFixed(2)}</td>
                        <td className="px-4 py-2.5 text-gray-400 text-xs">{new Date(s.updated_at).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </div>
    </AdminShell>
  );
}
