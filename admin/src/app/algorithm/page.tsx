'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import { Sliders, Save, RefreshCw } from 'lucide-react';

export default function AlgorithmPage() {
  const [configs, setConfigs] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [editValues, setEditValues] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState<string | null>(null);

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
    </AdminShell>
  );
}
