// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import { Sliders, Save, RefreshCw, BarChart2, ChevronDown, ChevronRight } from 'lucide-react';

function scoreColor(value: number): string {
  if (value > 0.05) return 'text-green-600';
  if (value >= -0.05) return 'text-gray-500';
  if (value >= -0.10) return 'text-amber-600';
  return 'text-red-600';
}

function scoreBg(value: number): string {
  if (value > 0.05) return 'bg-green-50';
  if (value >= -0.05) return '';
  if (value >= -0.10) return 'bg-amber-50';
  return 'bg-red-50';
}

export default function AlgorithmPage() {
  const [configs, setConfigs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [editValues, setEditValues] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState<string | null>(null);
  const [scores, setScores] = useState<any[]>([]);
  const [scoresLoading, setScoresLoading] = useState(false);
  const [showScores, setShowScores] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [showCompounding, setShowCompounding] = useState(false);

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

  const handleRefresh = async () => {
    setRefreshing(true);
    try {
      await api.refreshFeedScores();
      // Wait a few seconds for background job to complete, then reload
      setTimeout(() => {
        loadScores();
        setRefreshing(false);
      }, 5000);
    } catch {
      setRefreshing(false);
    }
  };

  const groupedConfigs = {
    feed: configs.filter((c: any) => c.key.startsWith('feed_')),
    tone: configs.filter((c: any) => c.key.startsWith('tone_')),
    video: configs.filter((c: any) => c.key.startsWith('video_')),
    harmony: configs.filter((c: any) => c.key.startsWith('harmony_')),
    moderation: configs.filter((c: any) => c.key.startsWith('moderation_')),
    other: configs.filter((c: any) =>
      !c.key.startsWith('feed_') &&
      !c.key.startsWith('moderation_') &&
      !c.key.startsWith('tone_') &&
      !c.key.startsWith('video_') &&
      !c.key.startsWith('harmony_')
    ),
  };

  const ConfigSection = ({ title, items, iconColor = 'text-brand-500' }: {
    title: string; items: any[]; iconColor?: string;
  }) => {
    if (items.length === 0) return null;
    return (
      <div className="card p-5">
        <div className="flex items-center gap-2 mb-4">
          <Sliders className={`w-5 h-5 ${iconColor}`} />
          <h3 className="text-lg font-semibold text-gray-900">{title}</h3>
        </div>
        <div className="space-y-4">
          {items.map((config: any) => (
            <div key={config.key} className="flex items-center gap-4">
              <div className="flex-1">
                <label className="text-sm font-medium text-gray-700">
                  {config.key.replace(/^(feed_|moderation_|tone_|video_|harmony_)/, '').replace(/_/g, ' ').replace(/\b\w/g, (l: string) => l.toUpperCase())}
                </label>
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
        </div>
      </div>
    );
  };

  return (
    <AdminOnlyGuard>
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Algorithm &amp; Feed Settings</h1>
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
          <ConfigSection title="Feed Ranking Weights" items={groupedConfigs.feed} />
          <ConfigSection title="Tone Scoring" items={groupedConfigs.tone} iconColor="text-purple-500" />
          <ConfigSection title="Video Boost" items={groupedConfigs.video} iconColor="text-blue-500" />
          <ConfigSection title="Harmony" items={groupedConfigs.harmony} iconColor="text-green-500" />
          <ConfigSection title="Moderation Thresholds" items={groupedConfigs.moderation} iconColor="text-red-500" />
          {groupedConfigs.other.length > 0 && (
            <ConfigSection title="Other Settings" items={groupedConfigs.other} />
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
          <div className="flex items-center gap-2">
            {showScores && (
              <button
                onClick={handleRefresh}
                disabled={refreshing}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-blue-600 text-white rounded-lg text-sm hover:bg-blue-700 disabled:opacity-50"
              >
                <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
                {refreshing ? 'Scoring...' : 'Refresh Scores Now'}
              </button>
            )}
            <button
              onClick={loadScores}
              className="flex items-center gap-1.5 px-3 py-1.5 border rounded-lg text-sm hover:bg-gray-50"
            >
              <RefreshCw className={`w-4 h-4 ${scoresLoading ? 'animate-spin' : ''}`} />
              {showScores ? 'Reload' : 'Load Scores'}
            </button>
          </div>
        </div>
        {showScores && (
          <div className="bg-white rounded-xl border overflow-hidden">
            {scoresLoading ? (
              <div className="p-6 text-center text-gray-400">Loading scores&hellip;</div>
            ) : scores.length === 0 ? (
              <div className="p-6 text-center text-gray-400">No scored posts yet</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-gray-50 border-b">
                    <tr>
                      <th className="px-3 py-3 text-left font-medium text-gray-600">Post</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Total</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Engage</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Quality</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Recency</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Network</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Personal</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Tone</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Video</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Harmony</th>
                      <th className="px-3 py-3 text-right font-medium text-gray-600">Mod</th>
                      <th className="px-3 py-3 text-left font-medium text-gray-600">Updated</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {scores.map((s: any) => (
                      <tr key={s.post_id} className="hover:bg-gray-50">
                        <td className="px-3 py-2.5 max-w-[200px]">
                          <p className="truncate text-gray-800" title={s.excerpt}>{s.excerpt || '\u2014'}</p>
                          <p className="text-xs text-gray-400 font-mono">{s.post_id.slice(0, 8)}&hellip;</p>
                        </td>
                        <td className="px-3 py-2.5 text-right font-semibold text-blue-700">
                          {Number(s.total_score).toFixed(3)}
                        </td>
                        <td className="px-3 py-2.5 text-right text-gray-600">{Number(s.engagement_score).toFixed(3)}</td>
                        <td className="px-3 py-2.5 text-right text-gray-600">{Number(s.quality_score).toFixed(3)}</td>
                        <td className="px-3 py-2.5 text-right text-gray-600">{Number(s.recency_score).toFixed(3)}</td>
                        <td className="px-3 py-2.5 text-right text-gray-600">{Number(s.network_score).toFixed(3)}</td>
                        <td className="px-3 py-2.5 text-right text-gray-600">{Number(s.personalization).toFixed(3)}</td>
                        <td className={`px-3 py-2.5 text-right font-medium ${scoreColor(Number(s.tone_score))} ${scoreBg(Number(s.tone_score))}`}>
                          {Number(s.tone_score).toFixed(3)}
                        </td>
                        <td className={`px-3 py-2.5 text-right font-medium ${scoreColor(Number(s.video_boost_score))} ${scoreBg(Number(s.video_boost_score))}`}>
                          {Number(s.video_boost_score).toFixed(3)}
                        </td>
                        <td className={`px-3 py-2.5 text-right font-medium ${scoreColor(Number(s.harmony_score))} ${scoreBg(Number(s.harmony_score))}`}>
                          {Number(s.harmony_score).toFixed(3)}
                        </td>
                        <td className={`px-3 py-2.5 text-right font-medium ${scoreColor(Number(s.moderation_penalty))} ${scoreBg(Number(s.moderation_penalty))}`}>
                          {Number(s.moderation_penalty).toFixed(3)}
                        </td>
                        <td className="px-3 py-2.5 text-gray-400 text-xs whitespace-nowrap">{new Date(s.updated_at).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Compounding Effects Reference */}
      <div className="mt-8 mb-8">
        <button
          onClick={() => setShowCompounding(!showCompounding)}
          className="flex items-center gap-2 text-gray-700 hover:text-gray-900"
        >
          {showCompounding ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
          <h2 className="text-lg font-semibold">Compounding Effects Reference</h2>
        </button>
        {showCompounding && (
          <div className="mt-4 card p-5">
            <p className="text-sm text-gray-500 mb-4">
              This table documents deliberate compounding for the worst content. Hostile content from repeatedly-reported users should be effectively invisible. Strong engagement or network signals can still surface content if the community genuinely values it.
            </p>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 border-b">
                  <tr>
                    <th className="px-4 py-3 text-left font-medium text-gray-600">Scenario</th>
                    <th className="px-4 py-3 text-right font-medium text-gray-600">Tone</th>
                    <th className="px-4 py-3 text-right font-medium text-gray-600">Moderation</th>
                    <th className="px-4 py-3 text-right font-medium text-gray-600">Net Effect</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  <tr className="bg-green-50">
                    <td className="px-4 py-2.5 text-gray-800">Positive post, 0 strikes</td>
                    <td className="px-4 py-2.5 text-right text-green-600 font-medium">+0.015</td>
                    <td className="px-4 py-2.5 text-right text-gray-500">0</td>
                    <td className="px-4 py-2.5 text-right text-green-600 font-semibold">+0.015</td>
                  </tr>
                  <tr>
                    <td className="px-4 py-2.5 text-gray-800">Neutral post, 0 strikes</td>
                    <td className="px-4 py-2.5 text-right text-gray-500">0</td>
                    <td className="px-4 py-2.5 text-right text-gray-500">0</td>
                    <td className="px-4 py-2.5 text-right text-gray-500 font-semibold">0</td>
                  </tr>
                  <tr className="bg-amber-50">
                    <td className="px-4 py-2.5 text-gray-800">Negative post, 1 strike</td>
                    <td className="px-4 py-2.5 text-right text-amber-600 font-medium">&minus;0.015</td>
                    <td className="px-4 py-2.5 text-right text-amber-600 font-medium">&minus;0.015</td>
                    <td className="px-4 py-2.5 text-right text-amber-600 font-semibold">&minus;0.030</td>
                  </tr>
                  <tr className="bg-red-50">
                    <td className="px-4 py-2.5 text-gray-800">Hostile post, 2 strikes</td>
                    <td className="px-4 py-2.5 text-right text-red-600 font-medium">&minus;0.040</td>
                    <td className="px-4 py-2.5 text-right text-red-600 font-medium">&minus;0.030</td>
                    <td className="px-4 py-2.5 text-right text-red-600 font-semibold">&minus;0.070</td>
                  </tr>
                  <tr className="bg-red-50">
                    <td className="px-4 py-2.5 text-gray-800">Hostile post, 3 strikes, 3 flags</td>
                    <td className="px-4 py-2.5 text-right text-red-600 font-medium">&minus;0.040</td>
                    <td className="px-4 py-2.5 text-right text-red-600 font-medium">&minus;0.075</td>
                    <td className="px-4 py-2.5 text-right text-red-600 font-semibold">&minus;0.115</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p className="text-xs text-gray-400 mt-3">
              Tone contribution = tone_score &times; feed_tone_weight (0.10). Moderation contribution = (strikes &times; 0.15 + min(flags &times; 0.10, 0.30)) &times; feed_moderation_penalty_weight (0.10). The algorithm penalizes toxicity but doesn&apos;t hard-censor &mdash; strong engagement can still surface content.
            </p>
          </div>
        )}
      </div>
    </AdminShell>
    </AdminOnlyGuard>
  );
}
