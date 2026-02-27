// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import {
  Plus, Play, Eye, Trash2, Power, PowerOff, RefreshCw, Newspaper, Rss,
  ChevronDown, ChevronUp, Bot, Clock, AlertCircle, CheckCircle, ExternalLink,
} from 'lucide-react';

// ─── Model Selector (Local Ollama only) ─────────

function stripPrefix(modelId: string): string {
  if (modelId.startsWith('local/')) return modelId.slice(6);
  return modelId;
}

function ModelSelector({ value, onChange, className }: { value: string; onChange: (v: string) => void; className?: string }) {
  const [localModels, setLocalModels] = useState<{ id: string; name: string }[]>([]);
  const [search, setSearch] = useState('');
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    setLoading(true);
    api.listLocalModels().then((data) => {
      setLocalModels((data.models || []).map((m: any) => ({ id: m.id, name: m.name || m.id })));
    }).finally(() => setLoading(false));
  }, []);

  const filtered = search
    ? localModels.filter((m) => m.id.toLowerCase().includes(search.toLowerCase()) || m.name.toLowerCase().includes(search.toLowerCase()))
    : localModels;

  const handleSelect = (rawId: string) => {
    onChange(`local/${rawId}`);
    setOpen(false);
    setSearch('');
  };

  const rawValue = stripPrefix(value);
  const displayName = localModels.find((m) => m.id === rawValue)?.name || value;

  return (
    <div className={`relative ${className || ''}`}>
      <button type="button" onClick={() => setOpen(!open)}
        className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm text-left truncate bg-white hover:bg-warm-50 transition-colors flex items-center gap-1.5">
        <span className="text-[9px] px-1.5 py-0.5 rounded font-bold flex-shrink-0 bg-purple-100 text-purple-700">Local</span>
        <span className="truncate">{loading ? 'Loading...' : displayName}</span>
      </button>
      {open && (
        <div className="absolute z-50 mt-1 w-full bg-white border border-warm-300 rounded-lg shadow-lg max-h-80 overflow-hidden flex flex-col min-w-[320px]">
          <input type="text" placeholder="Search local models..." value={search} onChange={(e) => setSearch(e.target.value)} autoFocus
            className="px-3 py-2 border-b border-warm-200 text-sm outline-none" />
          <div className="overflow-y-auto max-h-52">
            {filtered.length === 0 ? (
              <p className="p-3 text-xs text-gray-500">{loading ? 'Loading...' : 'No local models (is Ollama running?)'}</p>
            ) : (
              filtered.slice(0, 100).map((m) => (
                <button key={m.id} type="button"
                  onClick={() => handleSelect(m.id)}
                  className={`w-full text-left px-3 py-1.5 text-xs hover:bg-brand-50 transition-colors ${
                    m.id === rawValue ? 'bg-brand-50 text-brand-700 font-medium' : 'text-gray-700'
                  }`}>
                  <span className="block truncate font-medium">{m.name}</span>
                  <span className="block truncate text-[10px] text-gray-400 font-mono">{m.id}</span>
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}

const DEFAULT_NEWS_SOURCES = [
  { name: 'NPR', site: 'npr.org', enabled: true },
  { name: 'AP News', site: 'apnews.com', enabled: true },
  { name: 'Bring Me The News', site: 'bringmethenews.com', enabled: true },
];

const DEFAULT_NEWS_PROMPT = `You are a news curator for Sojorn, a social media platform. Your job is to write brief, engaging social media posts about news articles.

Rules:
- Keep posts under 280 characters (excluding the link)
- Be factual and neutral — no editorializing or opinion
- Include the article link at the end
- Do NOT use hashtags
- Do NOT use emojis
- Write in a professional but conversational tone
- Start with the most important fact or detail
- Do NOT include "Source:" or "via" attribution — the link speaks for itself`;

const DEFAULT_GENERAL_PROMPT = `You are a social media content creator for an official Sojorn account. Generate engaging, original posts that spark conversation.

Rules:
- Keep posts under 500 characters
- Be authentic and conversational
- Ask questions to encourage engagement
- Vary your tone and topics
- Do NOT use hashtags excessively (1-2 max if any)
- Do NOT be overly promotional`;

interface NewsSource {
  name: string;
  site?: string;
  rss_url?: string;
  enabled: boolean;
}

interface Config {
  id: string;
  profile_id: string;
  account_type: string;
  enabled: boolean;
  model_id: string;
  system_prompt: string;
  temperature: number;
  max_tokens: number;
  post_interval_minutes: number;
  max_posts_per_day: number;
  posts_today: number;
  last_posted_at: string | null;
  news_sources: NewsSource[] | string;
  last_fetched_at: string | null;
  handle: string;
  display_name: string;
  avatar_url: string;
}

interface OfficialProfile {
  profile_id: string;
  handle: string;
  display_name: string;
  avatar_url: string;
  bio: string;
  is_verified: boolean;
  has_config: boolean;
  config_id?: string;
}

export default function OfficialAccountsPage() {
  const [configs, setConfigs] = useState<Config[]>([]);
  const [profiles, setProfiles] = useState<OfficialProfile[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [setupProfile, setSetupProfile] = useState<OfficialProfile | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<Record<string, boolean>>({});
  const [actionResult, setActionResult] = useState<Record<string, { ok: boolean; message: string }>>({});

  const fetchAll = async () => {
    setLoading(true);
    const [configData, profileData] = await Promise.allSettled([
      api.listOfficialAccounts(),
      api.listOfficialProfiles(),
    ]);
    setConfigs(configData.status === 'fulfilled' ? (configData.value.configs || []) : []);
    setProfiles(profileData.status === 'fulfilled' ? (profileData.value.profiles || []) : []);
    setLoading(false);
  };

  const fetchConfigs = fetchAll;

  useEffect(() => { fetchAll(); }, []);

  const setAction = (id: string, loading: boolean, result?: { ok: boolean; message: string }) => {
    setActionLoading((p) => ({ ...p, [id]: loading }));
    if (result) setActionResult((p) => ({ ...p, [id]: result }));
  };

  const handleToggle = async (cfg: Config) => {
    setAction(cfg.id, true);
    try {
      await api.toggleOfficialAccount(cfg.id, !cfg.enabled);
      setAction(cfg.id, false, { ok: true, message: cfg.enabled ? 'Disabled' : 'Enabled' });
      fetchConfigs();
    } catch (e: any) {
      setAction(cfg.id, false, { ok: false, message: e.message });
    }
  };

  const handleDelete = async (cfg: Config) => {
    if (!confirm(`Delete official account config for @${cfg.handle}?`)) return;
    try {
      await api.deleteOfficialAccount(cfg.id);
      fetchConfigs();
    } catch (e: any) {
      alert(e.message);
    }
  };

  const handleTrigger = async (cfg: Config) => {
    setAction(cfg.id, true);
    try {
      const resp = await api.triggerOfficialPost(cfg.id);
      setAction(cfg.id, false, { ok: true, message: resp.body ? `Posted: ${resp.body.slice(0, 100)}...` : resp.message });
      fetchConfigs();
    } catch (e: any) {
      setAction(cfg.id, false, { ok: false, message: e.message });
    }
  };

  const handlePreview = async (cfg: Config) => {
    setAction(cfg.id, true);
    try {
      const resp = await api.previewOfficialPost(cfg.id);
      setAction(cfg.id, false, {
        ok: true,
        message: resp.preview
          ? `Preview: ${resp.preview}${resp.article_title ? `\n\nArticle: ${resp.article_title}` : ''}`
          : resp.message || 'No content to preview',
      });
    } catch (e: any) {
      setAction(cfg.id, false, { ok: false, message: e.message });
    }
  };

  return (
    <AdminOnlyGuard>
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Official Accounts</h1>
          <p className="text-gray-500 mt-1">Manage AI-powered official accounts and news automation</p>
        </div>
        <div className="flex gap-2">
          <button onClick={fetchConfigs} className="flex items-center gap-2 px-3 py-2 text-sm border border-warm-300 rounded-lg hover:bg-warm-200 transition-colors">
            <RefreshCw className="w-4 h-4" /> Refresh
          </button>
          <button onClick={() => setShowForm(!showForm)} className="flex items-center gap-2 px-4 py-2 text-sm bg-brand-500 text-white rounded-lg hover:bg-brand-600 transition-colors">
            <Plus className="w-4 h-4" /> Add Account
          </button>
        </div>
      </div>

      {showForm && <CreateAccountForm onDone={() => { setShowForm(false); fetchAll(); }} initialProfile={setupProfile} />}

      {/* Official Profiles Overview */}
      {!loading && profiles.length > 0 && (
        <div className="mb-6">
          <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wide mb-3">Official Profiles ({profiles.length})</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {profiles.map((p) => (
              <div key={p.profile_id} className="bg-white rounded-lg border border-warm-300 p-3 flex items-center gap-3">
                <div className="w-9 h-9 bg-brand-100 rounded-full flex items-center justify-center flex-shrink-0 text-brand-600 font-bold text-sm">
                  {p.avatar_url ? <img src={p.avatar_url} className="w-9 h-9 rounded-full object-cover" /> : p.handle[0]?.toUpperCase()}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5">
                    <span className="font-medium text-gray-900 text-sm truncate">@{p.handle}</span>
                    {p.is_verified && <CheckCircle className="w-3.5 h-3.5 text-brand-500 flex-shrink-0" />}
                  </div>
                  <p className="text-xs text-gray-500 truncate">{p.display_name}</p>
                </div>
                {p.has_config ? (
                  <span className="text-[10px] px-2 py-0.5 rounded-full bg-green-100 text-green-700 flex-shrink-0">Configured</span>
                ) : (
                  <button
                    onClick={() => { setSetupProfile(p); setShowForm(true); }}
                    className="text-xs px-2 py-1 bg-brand-50 text-brand-600 rounded hover:bg-brand-100 transition-colors flex-shrink-0"
                  >
                    Setup AI
                  </button>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {loading ? (
        <div className="text-center py-12 text-gray-500">Loading...</div>
      ) : configs.length === 0 ? (
        <div className="text-center py-12 text-gray-500">No official accounts configured yet.</div>
      ) : (
        <div className="space-y-4">
          {configs.map((cfg) => {
            const expanded = expandedId === cfg.id;
            const sources = typeof cfg.news_sources === 'string' ? JSON.parse(cfg.news_sources) : (cfg.news_sources || []);
            return (
              <div key={cfg.id} className="bg-white rounded-xl border border-warm-300 overflow-hidden">
                {/* Header */}
                <div className="p-4 flex items-center gap-4">
                  <div className="w-10 h-10 bg-brand-100 rounded-full flex items-center justify-center flex-shrink-0">
                    {cfg.account_type === 'news' ? <Newspaper className="w-5 h-5 text-brand-600" /> : cfg.account_type === 'rss' ? <Rss className="w-5 h-5 text-brand-600" /> : <Bot className="w-5 h-5 text-brand-600" />}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-gray-900">@{cfg.handle}</span>
                      <span className="text-xs px-2 py-0.5 rounded-full bg-warm-200 text-gray-600">{cfg.account_type}</span>
                      <span className={`text-xs px-2 py-0.5 rounded-full ${cfg.enabled ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
                        {cfg.enabled ? 'Active' : 'Disabled'}
                      </span>
                    </div>
                    <div className="flex items-center gap-4 text-xs text-gray-500 mt-1">
                      <span className="flex items-center gap-1"><Clock className="w-3 h-3" /> Every {cfg.post_interval_minutes}m</span>
                      <span>{cfg.posts_today}/{cfg.max_posts_per_day} today</span>
                      {cfg.last_posted_at && <span>Last: {new Date(cfg.last_posted_at).toLocaleString()}</span>}
                      <span className="text-gray-400 font-mono text-[10px]">{cfg.model_id}</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-1">
                    <button onClick={() => handlePreview(cfg)} disabled={actionLoading[cfg.id]} title="Preview AI output" className="p-2 rounded-lg hover:bg-warm-200 transition-colors text-gray-500 disabled:opacity-50">
                      <Eye className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleTrigger(cfg)} disabled={actionLoading[cfg.id]} title="Trigger post now" className="p-2 rounded-lg hover:bg-green-50 transition-colors text-green-600 disabled:opacity-50">
                      <Play className="w-4 h-4" />
                    </button>
                    <button onClick={() => handleToggle(cfg)} disabled={actionLoading[cfg.id]} title={cfg.enabled ? 'Disable' : 'Enable'} className="p-2 rounded-lg hover:bg-warm-200 transition-colors disabled:opacity-50">
                      {cfg.enabled ? <PowerOff className="w-4 h-4 text-red-500" /> : <Power className="w-4 h-4 text-green-500" />}
                    </button>
                    <button onClick={() => handleDelete(cfg)} title="Delete" className="p-2 rounded-lg hover:bg-red-50 transition-colors text-red-500">
                      <Trash2 className="w-4 h-4" />
                    </button>
                    <button onClick={() => setExpandedId(expanded ? null : cfg.id)} className="p-2 rounded-lg hover:bg-warm-200 transition-colors text-gray-500">
                      {expanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                    </button>
                  </div>
                </div>

                {/* Action result */}
                {actionResult[cfg.id] && (
                  <div className={`mx-4 mb-3 p-3 rounded-lg text-sm flex items-start gap-2 ${actionResult[cfg.id].ok ? 'bg-green-50 text-green-800 border border-green-200' : 'bg-red-50 text-red-800 border border-red-200'}`}>
                    {actionResult[cfg.id].ok ? <CheckCircle className="w-4 h-4 mt-0.5 flex-shrink-0" /> : <AlertCircle className="w-4 h-4 mt-0.5 flex-shrink-0" />}
                    <pre className="whitespace-pre-wrap break-all text-xs">{actionResult[cfg.id].message}</pre>
                    <button onClick={() => setActionResult((p) => { const n = { ...p }; delete n[cfg.id]; return n; })} className="ml-auto text-gray-400 hover:text-gray-600 text-xs">✕</button>
                  </div>
                )}

                {/* Expanded details */}
                {expanded && (
                  <div className="px-4 pb-4 border-t border-warm-200 pt-3 space-y-3">
                    <div className="grid grid-cols-2 gap-4 text-sm">
                      <div>
                        <span className="font-medium text-gray-600">Profile ID:</span>
                        <span className="ml-2 font-mono text-xs text-gray-500">{cfg.profile_id}</span>
                      </div>
                      <div>
                        <span className="font-medium text-gray-600">Model:</span>
                        <span className="ml-2 font-mono text-xs text-gray-500">{cfg.model_id}</span>
                      </div>
                      <div>
                        <span className="font-medium text-gray-600">Temperature:</span>
                        <span className="ml-2">{cfg.temperature}</span>
                      </div>
                      <div>
                        <span className="font-medium text-gray-600">Max Tokens:</span>
                        <span className="ml-2">{cfg.max_tokens}</span>
                      </div>
                    </div>

                    {cfg.system_prompt && (
                      <div>
                        <span className="text-sm font-medium text-gray-600">System Prompt:</span>
                        <pre className="mt-1 p-2 bg-warm-100 rounded text-xs text-gray-700 whitespace-pre-wrap max-h-40 overflow-y-auto">{cfg.system_prompt}</pre>
                      </div>
                    )}

                    {(cfg.account_type === 'news' || cfg.account_type === 'rss') && sources.length > 0 && (
                      <div>
                        <span className="text-sm font-medium text-gray-600">News Sources:</span>
                        <div className="mt-1 space-y-1">
                          {sources.map((src: NewsSource, i: number) => (
                            <div key={i} className="flex items-center gap-2 text-xs">
                              <span className={`w-2 h-2 rounded-full ${src.enabled ? 'bg-green-500' : 'bg-gray-300'}`} />
                              <span className="font-medium">{src.name}</span>
                              <span className="text-gray-400 font-mono">{src.site || src.rss_url}</span>
                              <a href={src.site ? `https://news.google.com/rss/search?q=site:${src.site}&hl=en-US&gl=US&ceid=US:en` : src.rss_url} target="_blank" className="text-brand-500 hover:underline flex items-center gap-1">
                                RSS <ExternalLink className="w-3 h-3" />
                              </a>
                            </div>
                          ))}
                        </div>
                        {cfg.last_fetched_at && (
                          <p className="text-xs text-gray-500 mt-1">Last fetched: {new Date(cfg.last_fetched_at).toLocaleString()}</p>
                        )}
                        <ArticlesPanel configId={cfg.id} />
                      </div>
                    )}

                    <EditAccountForm config={cfg} onDone={fetchConfigs} />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </AdminShell>
    </AdminOnlyGuard>
  );
}

// ─── Create Account Form ──────────────────────────────
function CreateAccountForm({ onDone, initialProfile }: { onDone: () => void; initialProfile?: OfficialProfile | null }) {
  const [handle, setHandle] = useState(initialProfile?.handle || '');
  const [accountType, setAccountType] = useState('general');
  const [modelId, setModelId] = useState('devstral:latest');
  const [systemPrompt, setSystemPrompt] = useState(DEFAULT_GENERAL_PROMPT);
  const [temperature, setTemperature] = useState(0.7);
  const [maxTokens, setMaxTokens] = useState(500);
  const [intervalMin, setIntervalMin] = useState(60);
  const [maxPerDay, setMaxPerDay] = useState(24);
  const [newsSources, setNewsSources] = useState<NewsSource[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (accountType === 'news') {
      setNewsSources(DEFAULT_NEWS_SOURCES);
      setSystemPrompt(DEFAULT_NEWS_PROMPT);
    } else if (accountType === 'rss') {
      setNewsSources(DEFAULT_NEWS_SOURCES);
      setSystemPrompt('');
    } else {
      setNewsSources([]);
      setSystemPrompt(DEFAULT_GENERAL_PROMPT);
    }
  }, [accountType]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      await api.upsertOfficialAccount({
        handle: handle.trim().toLowerCase(),
        account_type: accountType,
        enabled: false,
        model_id: modelId,
        system_prompt: systemPrompt,
        temperature,
        max_tokens: maxTokens,
        post_interval_minutes: intervalMin,
        max_posts_per_day: maxPerDay,
        news_sources: newsSources,
      });
      onDone();
    } catch (e: any) {
      setError(e.message);
    }
    setLoading(false);
  };

  return (
    <form onSubmit={handleSubmit} className="bg-white rounded-xl border border-warm-300 p-6 mb-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-4">Add Official Account</h2>

      <div className="grid grid-cols-3 gap-4 mb-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Handle *</label>
          <input type="text" required value={handle} onChange={(e) => setHandle(e.target.value)}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm" placeholder="newsbot" />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Account Type</label>
          <select value={accountType} onChange={(e) => setAccountType(e.target.value)}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm">
            <option value="general">General</option>
            <option value="news">News (AI Commentary)</option>
            <option value="rss">RSS (Link Only)</option>
            <option value="community">Community</option>
          </select>
        </div>
        {accountType !== 'rss' && (
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Model</label>
            <ModelSelector value={modelId} onChange={setModelId} />
          </div>
        )}
      </div>

      <div className="grid grid-cols-4 gap-4 mb-4">
        {accountType !== 'rss' && (
          <>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Temperature</label>
              <input type="number" step="0.1" min="0" max="2" value={temperature} onChange={(e) => setTemperature(Number(e.target.value))}
                className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Max Tokens</label>
              <input type="number" min="50" max="4000" value={maxTokens} onChange={(e) => setMaxTokens(Number(e.target.value))}
                className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm" />
            </div>
          </>
        )}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Interval (min)</label>
          <input type="number" min="5" value={intervalMin} onChange={(e) => setIntervalMin(Number(e.target.value))}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm" />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Max/Day</label>
          <input type="number" min="1" value={maxPerDay} onChange={(e) => setMaxPerDay(Number(e.target.value))}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm" />
        </div>
      </div>

      {accountType !== 'rss' && (
        <div className="mb-4">
          <label className="block text-sm font-medium text-gray-700 mb-1">System Prompt</label>
          <textarea value={systemPrompt} onChange={(e) => setSystemPrompt(e.target.value)} rows={6}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm font-mono" />
        </div>
      )}

      {(accountType === 'news' || accountType === 'rss') && (
        <div className="mb-4">
          <label className="block text-sm font-medium text-gray-700 mb-2">News Sources (RSS Feeds)</label>
          {newsSources.map((src, i) => (
            <div key={i} className="flex items-center gap-2 mb-2">
              <input type="checkbox" checked={src.enabled}
                onChange={(e) => { const n = [...newsSources]; n[i] = { ...n[i], enabled: e.target.checked }; setNewsSources(n); }}
                className="w-4 h-4 rounded" />
              <input type="text" value={src.name} placeholder="Name"
                onChange={(e) => { const n = [...newsSources]; n[i] = { ...n[i], name: e.target.value }; setNewsSources(n); }}
                className="w-32 px-2 py-1 border border-warm-300 rounded text-sm" />
              <input type="text" value={src.site || ''} placeholder="site domain (e.g. npr.org)"
                onChange={(e) => { const n = [...newsSources]; n[i] = { ...n[i], site: e.target.value }; setNewsSources(n); }}
                className="flex-1 px-2 py-1 border border-warm-300 rounded text-sm font-mono" />
              <button type="button" onClick={() => setNewsSources(newsSources.filter((_, j) => j !== i))}
                className="text-red-500 hover:text-red-700 text-sm">✕</button>
            </div>
          ))}
          <button type="button" onClick={() => setNewsSources([...newsSources, { name: '', site: '', enabled: true }])}
            className="text-sm text-brand-500 hover:text-brand-600 flex items-center gap-1 mt-1">
            <Plus className="w-3 h-3" /> Add Source
          </button>
        </div>
      )}

      {error && (
        <div className="mb-4 p-3 rounded-lg text-sm bg-red-50 text-red-800 border border-red-200 flex items-center gap-2">
          <AlertCircle className="w-4 h-4" /> {error}
        </div>
      )}

      <div className="flex gap-2">
        <button type="submit" disabled={loading}
          className="px-4 py-2 bg-brand-500 text-white rounded-lg text-sm font-medium hover:bg-brand-600 disabled:opacity-50">
          {loading ? 'Creating...' : 'Create Account Config'}
        </button>
        <button type="button" onClick={() => { /* parent handles close via onDone */ }}
          className="px-4 py-2 border border-warm-300 rounded-lg text-sm hover:bg-warm-200">
          Cancel
        </button>
      </div>
    </form>
  );
}

// ─── Edit Account Form (inline) ───────────────────────
function EditAccountForm({ config, onDone }: { config: Config; onDone: () => void }) {
  const sources = typeof config.news_sources === 'string' ? JSON.parse(config.news_sources) : (config.news_sources || []);
  const [modelId, setModelId] = useState(config.model_id);
  const [systemPrompt, setSystemPrompt] = useState(config.system_prompt);
  const [temperature, setTemperature] = useState(config.temperature);
  const [maxTokens, setMaxTokens] = useState(config.max_tokens);
  const [intervalMin, setIntervalMin] = useState(config.post_interval_minutes);
  const [maxPerDay, setMaxPerDay] = useState(config.max_posts_per_day);
  const [newsSources, setNewsSources] = useState<NewsSource[]>(sources);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; msg: string } | null>(null);

  const handleSave = async () => {
    setLoading(true);
    setResult(null);
    try {
      await api.upsertOfficialAccount({
        profile_id: config.profile_id,
        account_type: config.account_type,
        enabled: config.enabled,
        model_id: modelId,
        system_prompt: systemPrompt,
        temperature,
        max_tokens: maxTokens,
        post_interval_minutes: intervalMin,
        max_posts_per_day: maxPerDay,
        news_sources: newsSources,
      });
      setResult({ ok: true, msg: 'Saved' });
      onDone();
    } catch (e: any) {
      setResult({ ok: false, msg: e.message });
    }
    setLoading(false);
  };

  return (
    <div className="border-t border-warm-200 pt-3 mt-3">
      <h3 className="text-sm font-semibold text-gray-700 mb-3">Edit Configuration</h3>
      <div className="grid grid-cols-4 gap-3 mb-3">
        {config.account_type !== 'rss' && (
          <>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Model</label>
              <ModelSelector value={modelId} onChange={setModelId} />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Temperature</label>
              <input type="number" step="0.1" min="0" max="2" value={temperature} onChange={(e) => setTemperature(Number(e.target.value))}
                className="w-full px-2 py-1.5 border border-warm-300 rounded text-xs" />
            </div>
          </>
        )}
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Interval (min)</label>
          <input type="number" min="5" value={intervalMin} onChange={(e) => setIntervalMin(Number(e.target.value))}
            className="w-full px-2 py-1.5 border border-warm-300 rounded text-xs" />
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-600 mb-1">Max/Day</label>
          <input type="number" min="1" value={maxPerDay} onChange={(e) => setMaxPerDay(Number(e.target.value))}
            className="w-full px-2 py-1.5 border border-warm-300 rounded text-xs" />
        </div>
      </div>
      {config.account_type !== 'rss' && (
        <div className="mb-3">
          <label className="block text-xs font-medium text-gray-600 mb-1">System Prompt</label>
          <textarea value={systemPrompt} onChange={(e) => setSystemPrompt(e.target.value)} rows={4}
            className="w-full px-2 py-1.5 border border-warm-300 rounded text-xs font-mono" />
        </div>
      )}

      {(config.account_type === 'news' || config.account_type === 'rss') && (
        <div className="mb-3">
          <label className="block text-xs font-medium text-gray-600 mb-1">News Sources</label>
          {newsSources.map((src, i) => (
            <div key={i} className="flex items-center gap-2 mb-1">
              <input type="checkbox" checked={src.enabled}
                onChange={(e) => { const n = [...newsSources]; n[i] = { ...n[i], enabled: e.target.checked }; setNewsSources(n); }}
                className="w-3 h-3 rounded" />
              <input type="text" value={src.name}
                onChange={(e) => { const n = [...newsSources]; n[i] = { ...n[i], name: e.target.value }; setNewsSources(n); }}
                className="w-28 px-2 py-1 border border-warm-300 rounded text-xs" />
              <input type="text" value={src.site || ''}
                onChange={(e) => { const n = [...newsSources]; n[i] = { ...n[i], site: e.target.value }; setNewsSources(n); }}
                className="flex-1 px-2 py-1 border border-warm-300 rounded text-xs font-mono" />
              <button type="button" onClick={() => setNewsSources(newsSources.filter((_, j) => j !== i))}
                className="text-red-500 text-xs">✕</button>
            </div>
          ))}
          <button type="button" onClick={() => setNewsSources([...newsSources, { name: '', site: '', enabled: true }])}
            className="text-xs text-brand-500 hover:text-brand-600 flex items-center gap-1 mt-1">
            <Plus className="w-3 h-3" /> Add
          </button>
        </div>
      )}

      <div className="flex items-center gap-2">
        <button onClick={handleSave} disabled={loading}
          className="px-3 py-1.5 bg-brand-500 text-white rounded text-xs font-medium hover:bg-brand-600 disabled:opacity-50">
          {loading ? 'Saving...' : 'Save Changes'}
        </button>
        {result && (
          <span className={`text-xs ${result.ok ? 'text-green-600' : 'text-red-600'}`}>{result.msg}</span>
        )}
      </div>
    </div>
  );
}

// ─── Articles Pipeline Panel ─────────────────────────
type PipelineTab = 'discovered' | 'posted' | 'failed' | 'skipped';
interface ArticleStats { discovered: number; posted: number; failed: number; skipped: number; total: number; }

function groupByDate(articles: any[], dateField: string): Record<string, any[]> {
  const groups: Record<string, any[]> = {};
  for (const a of articles) {
    const raw = a[dateField] || a.discovered_at;
    const date = raw ? new Date(raw).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }) : 'Unknown';
    if (!groups[date]) groups[date] = [];
    groups[date].push(a);
  }
  return groups;
}

function ArticlesPanel({ configId }: { configId: string }) {
  const [articles, setArticles] = useState<any[]>([]);
  const [stats, setStats] = useState<ArticleStats | null>(null);
  const [tab, setTab] = useState<PipelineTab>('discovered');
  const [loading, setLoading] = useState(false);
  const [bulkCount, setBulkCount] = useState(5);
  const [posting, setPosting] = useState(false);
  const [postResult, setPostResult] = useState<{ ok: boolean; msg: string } | null>(null);
  const [actionLoading, setActionLoading] = useState<Record<string, boolean>>({});
  const [cleanupDate, setCleanupDate] = useState('');
  const [cleanupAction, setCleanupAction] = useState<'skip' | 'delete'>('skip');
  const [cleanupLoading, setCleanupLoading] = useState(false);

  const fetchTab = async (t: PipelineTab) => {
    setLoading(true);
    try {
      if (t === 'discovered') {
        const data = await api.fetchNewsArticles(configId);
        setArticles(data.articles || []);
        if (data.stats) setStats(data.stats);
      } else {
        const data = await api.getPostedArticles(configId, 100, t);
        setArticles(data.articles || []);
        if (data.stats) setStats(data.stats);
      }
    } catch (e: any) {
      setArticles([]);
      setPostResult({ ok: false, msg: `Fetch failed: ${e.message}` });
    }
    setLoading(false);
  };

  useEffect(() => { fetchTab(tab); }, [tab]);

  const handleBulkPost = async (count: number | 'all') => {
    setPosting(true);
    setPostResult(null);
    try {
      const resp = await api.triggerOfficialPost(configId, count);
      const n = resp.posted?.length || 0;
      const errs = resp.errors?.length || 0;
      let msg = `Posted ${n} article(s)`;
      if (errs > 0) msg += `, ${errs} error(s)`;
      setPostResult({ ok: errs === 0, msg });
      if (resp.stats) setStats(resp.stats);
      fetchTab(tab);
    } catch (e: any) {
      setPostResult({ ok: false, msg: e.message });
    }
    setPosting(false);
  };

  const handleArticleAction = async (articleId: string, action: 'post' | 'skip' | 'delete') => {
    setActionLoading((p) => ({ ...p, [articleId]: true }));
    try {
      if (action === 'post') await api.postSpecificArticle(articleId);
      else if (action === 'skip') await api.skipArticle(articleId);
      else if (action === 'delete') await api.deleteArticle(articleId);
      fetchTab(tab);
    } catch (e: any) {
      setPostResult({ ok: false, msg: `${action} failed: ${e.message}` });
    }
    setActionLoading((p) => ({ ...p, [articleId]: false }));
  };

  const handleCleanup = async () => {
    if (!cleanupDate) return;
    if (!confirm(`${cleanupAction === 'delete' ? 'Permanently delete' : 'Skip'} all pending articles before ${cleanupDate}?`)) return;
    setCleanupLoading(true);
    setPostResult(null);
    try {
      const resp = await api.cleanupPendingArticles(configId, cleanupDate, cleanupAction);
      setPostResult({ ok: true, msg: resp.message });
      if (resp.stats) setStats(resp.stats);
      fetchTab(tab);
    } catch (e: any) {
      setPostResult({ ok: false, msg: e.message });
    }
    setCleanupLoading(false);
  };

  const tabConfig: { key: PipelineTab; label: string; color: string; bgColor: string }[] = [
    { key: 'discovered', label: 'Pending', color: 'text-blue-700', bgColor: 'bg-blue-100' },
    { key: 'posted',     label: 'Posted',  color: 'text-green-700', bgColor: 'bg-green-100' },
    { key: 'failed',     label: 'Failed',  color: 'text-red-700', bgColor: 'bg-red-100' },
    { key: 'skipped',    label: 'Skipped', color: 'text-gray-600', bgColor: 'bg-gray-100' },
  ];

  const getCount = (key: PipelineTab) => stats ? stats[key] : 0;

  const dateField = tab === 'posted' ? 'posted_at' : tab === 'discovered' ? 'discovered_at' : 'discovered_at';
  const grouped = groupByDate(articles, tab === 'discovered' ? 'pub_date' : dateField);

  return (
    <div className="mt-3 border border-warm-200 rounded-lg overflow-hidden">
      {/* Stats bar */}
      {stats && (
        <div className="flex items-center gap-3 px-3 py-2 bg-warm-50 border-b border-warm-200">
          <span className="text-[10px] font-semibold text-gray-500 uppercase tracking-wide">Pipeline</span>
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-blue-100 text-blue-700 font-medium">{stats.discovered} pending</span>
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-green-100 text-green-700 font-medium">{stats.posted} posted</span>
          {stats.failed > 0 && <span className="text-[10px] px-1.5 py-0.5 rounded bg-red-100 text-red-700 font-medium">{stats.failed} failed</span>}
          {stats.skipped > 0 && <span className="text-[10px] px-1.5 py-0.5 rounded bg-gray-100 text-gray-600 font-medium">{stats.skipped} skipped</span>}
          <span className="text-[10px] text-gray-400 ml-auto">{stats.total} total</span>
        </div>
      )}

      {/* Tabs */}
      <div className="flex bg-warm-100">
        {tabConfig.map((t) => (
          <button key={t.key} onClick={() => setTab(t.key)}
            className={`px-3 py-1.5 text-xs font-medium transition-colors ${
              tab === t.key ? 'bg-white text-gray-900 border-b-2 border-brand-500' : 'text-gray-500 hover:text-gray-700'
            }`}>
            {t.label}
            {stats && getCount(t.key) > 0 && (
              <span className={`ml-1.5 text-[10px] px-1 py-0.5 rounded ${t.bgColor} ${t.color}`}>{getCount(t.key)}</span>
            )}
          </button>
        ))}
        <button onClick={() => fetchTab(tab)} className="ml-auto px-2 py-1 text-gray-400 hover:text-gray-600">
          <RefreshCw className="w-3 h-3" />
        </button>
      </div>

      {/* Bulk post controls — only on discovered tab */}
      {tab === 'discovered' && stats && stats.discovered > 0 && (
        <div className="border-b border-warm-200">
          <div className="flex items-center gap-2 px-3 py-2 bg-blue-50">
            <span className="text-[10px] font-medium text-gray-600">Post:</span>
            <input type="number" min={1} max={stats.discovered} value={bulkCount}
              onChange={(e) => setBulkCount(Math.max(1, Number(e.target.value)))}
              className="w-14 px-1.5 py-1 border border-warm-300 rounded text-xs text-center" />
            <button onClick={() => handleBulkPost(bulkCount)} disabled={posting}
              className="px-2.5 py-1 bg-brand-500 text-white rounded text-xs font-medium hover:bg-brand-600 disabled:opacity-50">
              {posting ? 'Posting...' : `Post ${bulkCount}`}
            </button>
            <button onClick={() => handleBulkPost('all')} disabled={posting}
              className="px-2.5 py-1 bg-green-600 text-white rounded text-xs font-medium hover:bg-green-700 disabled:opacity-50">
              {posting ? 'Posting...' : `Post All (${stats.discovered})`}
            </button>
          </div>
          <div className="flex items-center gap-2 px-3 py-2 bg-amber-50">
            <span className="text-[10px] font-medium text-gray-600">Cleanup before:</span>
            <input type="date" value={cleanupDate} onChange={(e) => setCleanupDate(e.target.value)}
              className="px-1.5 py-1 border border-warm-300 rounded text-xs" />
            <select value={cleanupAction} onChange={(e) => setCleanupAction(e.target.value as 'skip' | 'delete')}
              className="px-1.5 py-1 border border-warm-300 rounded text-xs">
              <option value="skip">Skip</option>
              <option value="delete">Delete</option>
            </select>
            <button onClick={handleCleanup} disabled={cleanupLoading || !cleanupDate}
              className="px-2.5 py-1 bg-amber-600 text-white rounded text-xs font-medium hover:bg-amber-700 disabled:opacity-50">
              {cleanupLoading ? 'Cleaning...' : 'Cleanup'}
            </button>
          </div>
        </div>
      )}

      {/* Result message */}
      {postResult && (
        <div className={`flex items-center gap-2 px-3 py-1.5 text-xs border-b border-warm-200 ${postResult.ok ? 'bg-green-50 text-green-700' : 'bg-red-50 text-red-700'}`}>
          {postResult.ok ? <CheckCircle className="w-3 h-3" /> : <AlertCircle className="w-3 h-3" />}
          <span>{postResult.msg}</span>
          <button onClick={() => setPostResult(null)} className="ml-auto text-gray-400 hover:text-gray-600 text-[10px]">✕</button>
        </div>
      )}

      {/* Article list grouped by date */}
      <div className="max-h-80 overflow-y-auto">
        {loading ? (
          <p className="p-3 text-xs text-gray-500">Loading...</p>
        ) : articles.length === 0 ? (
          <p className="p-3 text-xs text-gray-500">No {tab} articles</p>
        ) : (
          Object.entries(grouped).map(([date, items]) => (
            <div key={date}>
              <div className="sticky top-0 px-3 py-1 bg-warm-100 border-b border-warm-200">
                <span className="text-[10px] font-semibold text-gray-500 uppercase tracking-wide">{date}</span>
                <span className="text-[10px] text-gray-400 ml-2">({items.length})</span>
              </div>
              {items.map((a: any) => {
                const id = a.id || a.link;
                const isActioning = actionLoading[id];
                return (
                  <div key={id} className="px-3 py-1.5 border-b border-warm-100 last:border-0 hover:bg-warm-50 group">
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] px-1.5 py-0.5 bg-warm-200 rounded text-gray-600 flex-shrink-0">
                        {a.source || a.source_name}
                      </span>
                      <a href={a.link} target="_blank" rel="noopener noreferrer"
                        className="text-xs font-medium text-brand-600 hover:underline flex items-center gap-1 truncate flex-1 min-w-0">
                        <span className="truncate">{a.title}</span>
                        <ExternalLink className="w-3 h-3 flex-shrink-0" />
                      </a>
                      {a.posted_at && (
                        <span className="text-[10px] text-gray-400 flex-shrink-0">
                          {new Date(a.posted_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        </span>
                      )}
                      {/* Per-article actions for pending tab */}
                      {tab === 'discovered' && a.id && (
                        <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0">
                          <button onClick={() => handleArticleAction(a.id, 'post')} disabled={isActioning}
                            title="Post this article" className="p-1 rounded hover:bg-green-100 text-green-600 disabled:opacity-50">
                            <Play className="w-3 h-3" />
                          </button>
                          <button onClick={() => handleArticleAction(a.id, 'skip')} disabled={isActioning}
                            title="Skip this article" className="p-1 rounded hover:bg-amber-100 text-amber-600 disabled:opacity-50">
                            <Clock className="w-3 h-3" />
                          </button>
                          <button onClick={() => handleArticleAction(a.id, 'delete')} disabled={isActioning}
                            title="Delete this article" className="p-1 rounded hover:bg-red-100 text-red-500 disabled:opacity-50">
                            <Trash2 className="w-3 h-3" />
                          </button>
                        </div>
                      )}
                      {/* Delete action for other tabs */}
                      {tab !== 'discovered' && a.id && (
                        <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0">
                          <button onClick={() => handleArticleAction(a.id, 'delete')} disabled={isActioning}
                            title="Delete this article" className="p-1 rounded hover:bg-red-100 text-red-500 disabled:opacity-50">
                            <Trash2 className="w-3 h-3" />
                          </button>
                        </div>
                      )}
                    </div>
                    {a.description && tab === 'discovered' && (
                      <p className="text-[10px] text-gray-500 mt-0.5 ml-[calc(1.5rem+0.5rem)] line-clamp-1">{a.description}</p>
                    )}
                    {a.error_message && <p className="text-[10px] text-red-500 mt-0.5">{a.error_message}</p>}
                  </div>
                );
              })}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
