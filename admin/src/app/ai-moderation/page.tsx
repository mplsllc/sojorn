'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useEffect, useState, useCallback, useRef } from 'react';
import { Brain, Search, Check, Power, PowerOff, ChevronDown, Play, Loader2, Eye, MessageSquare, Video, Sparkles, Shield, MapPin, Users, AlertTriangle, RefreshCw, Server, Cloud, Cpu, Zap } from 'lucide-react';

const MODERATION_TYPES = [
  { key: 'text', label: 'Text Moderation', icon: MessageSquare, desc: 'Analyze post text, comments, and captions for policy violations' },
  { key: 'image', label: 'Image Moderation', icon: Eye, desc: 'Analyze uploaded images for inappropriate content (requires vision model)' },
  { key: 'video', label: 'Video Moderation', icon: Video, desc: 'Analyze video frames extracted from Quips (requires vision model)' },
  { key: 'group_text', label: 'Group Chat Moderation', icon: Users, desc: 'AI moderation for private group messages — pre-send check before E2EE encryption' },
  { key: 'group_image', label: 'Group Image Moderation', icon: Shield, desc: 'AI moderation for images shared in private groups (requires vision model)' },
  { key: 'beacon_text', label: 'Beacon Text Moderation', icon: MapPin, desc: 'AI moderation for beacon reports — safety/incident content on the map' },
  { key: 'beacon_image', label: 'Beacon Image Moderation', icon: AlertTriangle, desc: 'AI moderation for beacon images — photos attached to safety reports (requires vision model)' },
];

interface ModelInfo {
  id: string;
  name: string;
  description?: string;
  pricing: { prompt: string; completion: string; image?: string };
  context_length: number;
  architecture?: Record<string, any>;
}

interface ModerationConfig {
  id: string;
  moderation_type: string;
  model_id: string;
  model_name: string;
  system_prompt: string;
  enabled: boolean;
  engines: string[];
  updated_at: string;
}

const ALL_ENGINES = [
  { id: 'local_ai', label: 'Local AI', desc: 'Ollama llama-guard (free, on-server)', icon: Cpu },
  { id: 'openrouter', label: 'OpenRouter', desc: 'Cloud models (configurable below)', icon: Cloud },
  { id: 'openai', label: 'OpenAI', desc: 'Three Poisons moderation API', icon: Server },
  { id: 'google', label: 'Google Vision', desc: 'SafeSearch image moderation API', icon: Eye },
];

interface EngineInfo {
  id: string;
  name: string;
  description: string;
  status: string;
  configured: boolean;
  details?: any;
}

export default function AIModerationPage() {
  const [configs, setConfigs] = useState<ModerationConfig[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeType, setActiveType] = useState('text');
  const [engines, setEngines] = useState<EngineInfo[]>([]);
  const [enginesLoading, setEnginesLoading] = useState(true);

  const loadConfigs = useCallback(() => {
    setLoading(true);
    api.getAIModerationConfigs()
      .then((data) => setConfigs(data.configs || []))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  const loadEngines = useCallback(() => {
    setEnginesLoading(true);
    api.getAIEngines()
      .then((data) => setEngines(data.engines || []))
      .catch(() => {})
      .finally(() => setEnginesLoading(false));
  }, []);

  useEffect(() => { loadConfigs(); loadEngines(); }, [loadConfigs, loadEngines]);

  const getConfig = (type: string) => configs.find(c => c.moderation_type === type);

  return (
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
          <Brain className="w-6 h-6" /> AI Moderation
        </h1>
        <p className="text-sm text-gray-500 mt-1">Configure and monitor AI moderation engines</p>
      </div>

      {/* Engines Status Panel */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-sm font-semibold text-gray-700 uppercase tracking-wider flex items-center gap-1.5">
            <Zap className="w-4 h-4" /> Moderation Engines
          </h2>
          <button onClick={loadEngines} disabled={enginesLoading} className="text-xs text-gray-400 hover:text-gray-600 flex items-center gap-1">
            <RefreshCw className={`w-3 h-3 ${enginesLoading ? 'animate-spin' : ''}`} /> Refresh
          </button>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {engines.map((engine) => {
            const Icon = engine.id === 'local_ai' ? Cpu : engine.id === 'openrouter' ? Cloud : engine.id === 'google' ? Eye : Server;
            const statusColor = engine.status === 'ready' ? 'text-green-600 bg-green-50 border-green-200' :
              engine.status === 'down' ? 'text-red-600 bg-red-50 border-red-200' :
              engine.status === 'not_configured' ? 'text-gray-400 bg-gray-50 border-gray-200' :
              'text-amber-600 bg-amber-50 border-amber-200';
            const dotColor = engine.status === 'ready' ? 'bg-green-500' :
              engine.status === 'down' ? 'bg-red-500' :
              engine.status === 'not_configured' ? 'bg-gray-300' : 'bg-amber-500';
            return (
              <div key={engine.id} className={`rounded-xl border p-4 ${statusColor}`}>
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Icon className="w-5 h-5" />
                    <span className="font-semibold text-sm">{engine.name}</span>
                  </div>
                  <span className="flex items-center gap-1.5 text-xs font-medium">
                    <span className={`w-2 h-2 rounded-full ${dotColor} ${engine.status === 'ready' ? 'animate-pulse' : ''}`} />
                    {engine.status === 'ready' ? 'Online' : engine.status === 'down' ? 'Down' : engine.status === 'not_configured' ? 'Not Configured' : engine.status}
                  </span>
                </div>
                <p className="text-xs opacity-75 mb-2">{engine.description}</p>
                {engine.details && engine.id === 'local_ai' && engine.status === 'ready' && (
                  <div className="flex gap-3 text-xs opacity-60">
                    <span>Redis: {engine.details.redis}</span>
                    <span>Ollama: {engine.details.ollama}</span>
                    <span>Judge Q: {engine.details.queue_judge}</span>
                    <span>Writer Q: {engine.details.queue_writer}</span>
                  </div>
                )}
                {engine.details && engine.id === 'openrouter' && (
                  <div className="text-xs opacity-60">
                    {engine.details.enabled_configs}/{engine.details.total_configs} configs enabled
                  </div>
                )}
              </div>
            );
          })}
          {engines.length === 0 && !enginesLoading && (
            <div className="col-span-3 text-center text-sm text-gray-400 py-4">No engine data available</div>
          )}
        </div>
      </div>

      {/* Config Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        {MODERATION_TYPES.map((mt) => {
          const config = getConfig(mt.key);
          const Icon = mt.icon;
          return (
            <button
              key={mt.key}
              onClick={() => setActiveType(mt.key)}
              className={`card p-4 text-left transition-all ${
                activeType === mt.key ? 'ring-2 ring-brand-500 shadow-md' : 'hover:shadow-sm'
              }`}
            >
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <Icon className="w-5 h-5 text-gray-600" />
                  <span className="font-semibold text-gray-900 text-sm">{mt.label}</span>
                </div>
                {config?.enabled ? (
                  <span className="flex items-center gap-1 text-xs font-medium text-green-700 bg-green-100 px-2 py-0.5 rounded-full">
                    <Power className="w-3 h-3" /> On
                  </span>
                ) : (
                  <span className="flex items-center gap-1 text-xs font-medium text-gray-400 bg-gray-100 px-2 py-0.5 rounded-full">
                    <PowerOff className="w-3 h-3" /> Off
                  </span>
                )}
              </div>
              <p className="text-xs text-gray-400 mb-2">{mt.desc}</p>
              {config?.engines && config.engines.length > 0 ? (
                <div className="flex gap-1 mb-1 flex-wrap">
                  {config.engines.map(e => (
                    <span key={e} className="text-[10px] font-medium bg-brand-100 text-brand-700 px-1.5 py-0.5 rounded">
                      {e === 'local_ai' ? 'Local AI' : e === 'openrouter' ? 'OpenRouter' : e === 'google' ? 'Google Vision' : 'OpenAI'}
                    </span>
                  ))}
                </div>
              ) : (
                <div className="flex gap-1 mb-1">
                  <span className="text-[10px] text-gray-300 italic">No engines configured</span>
                </div>
              )}
              {config?.model_id ? (
                <p className="text-xs font-mono text-brand-600 truncate">{config.model_name || config.model_id}</p>
              ) : (
                <p className="text-xs text-gray-300 italic">No model selected</p>
              )}
            </button>
          );
        })}
      </div>

      {/* Active Config Editor */}
      <ConfigEditor
        key={activeType}
        moderationType={activeType}
        config={getConfig(activeType)}
        onSaved={loadConfigs}
      />
    </AdminShell>
  );
}

// ─── Local AI models available on Ollama ─────────
const LOCAL_MODELS = [
  { id: 'llama-guard3:1b', name: 'LLaMA Guard 3 (1B)', desc: 'Content safety classifier — fast, accurate moderation', type: 'judge' },
  { id: 'qwen2.5:7b-instruct-q4_K_M', name: 'Qwen 2.5 (7B)', desc: 'General-purpose reasoning model — slower, deeper analysis', type: 'writer' },
];

// ─── Config Editor for a single moderation type ─────────

function ConfigEditor({ moderationType, config, onSaved }: {
  moderationType: string;
  config?: ModerationConfig;
  onSaved: () => void;
}) {
  const [modelId, setModelId] = useState(config?.model_id || '');
  const [modelName, setModelName] = useState(config?.model_name || '');
  const [systemPrompt, setSystemPrompt] = useState(config?.system_prompt || '');
  const [enabled, setEnabled] = useState(config?.enabled || false);
  const [engines, setEngines] = useState<string[]>(config?.engines || ['local_ai', 'openrouter', 'openai']);
  const [saving, setSaving] = useState(false);
  const [activeTab, setActiveTab] = useState<string>(engines[0] || 'local_ai');

  const toggleEngine = (engineId: string) => {
    setEngines(prev => {
      const next = prev.includes(engineId) ? prev.filter(e => e !== engineId) : [...prev, engineId];
      // If we just enabled this engine, switch tab to it
      if (!prev.includes(engineId)) setActiveTab(engineId);
      // If we disabled the active tab, switch to first remaining
      if (engineId === activeTab && next.length > 0) setActiveTab(next[0]);
      return next;
    });
  };

  // OpenRouter model picker
  const [showPicker, setShowPicker] = useState(false);
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [modelsLoading, setModelsLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [capability, setCapability] = useState('');
  const searchTimer = useRef<any>(null);

  // Test
  const [testInput, setTestInput] = useState('');
  const [testResponse, setTestResponse] = useState<any>(null);
  const [testing, setTesting] = useState(false);
  const [testEngine, setTestEngine] = useState<string>(engines[0] || 'local_ai');

  const loadModels = useCallback((search?: string, cap?: string) => {
    setModelsLoading(true);
    api.listOpenRouterModels({ search, capability: cap })
      .then((data) => setModels(data.models || []))
      .catch(() => {})
      .finally(() => setModelsLoading(false));
  }, []);

  useEffect(() => {
    if (showPicker) loadModels(searchTerm || undefined, capability || undefined);
  }, [showPicker]);

  const onSearchChange = (val: string) => {
    setSearchTerm(val);
    if (searchTimer.current) clearTimeout(searchTimer.current);
    searchTimer.current = setTimeout(() => {
      loadModels(val || undefined, capability || undefined);
    }, 400);
  };

  const onCapabilityChange = (val: string) => {
    setCapability(val);
    loadModels(searchTerm || undefined, val || undefined);
  };

  const selectModel = (m: ModelInfo) => {
    setModelId(m.id);
    setModelName(m.name);
    setShowPicker(false);
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await api.setAIModerationConfig({
        moderation_type: moderationType,
        model_id: modelId,
        model_name: modelName,
        system_prompt: systemPrompt,
        enabled,
        engines,
      });
      onSaved();
    } catch (e: any) {
      alert(e.message);
    } finally {
      setSaving(false);
    }
  };

  const handleTest = async () => {
    if (!testInput.trim()) return;
    setTesting(true);
    setTestResponse(null);
    try {
      const isImage = moderationType.includes('image') || moderationType === 'video';
      const data: any = {
        moderation_type: moderationType,
        engine: testEngine,
      };
      if (isImage) {
        data.image_url = testInput;
      } else {
        data.content = testInput;
      }
      const res = await api.testAIModeration(data);
      setTestResponse(res);
    } catch (e: any) {
      setTestResponse({ error: e.message, engine: testEngine, moderation_type: moderationType, input: testInput });
    } finally {
      setTesting(false);
    }
  };

  const isFree = (m: ModelInfo) => m.pricing.prompt === '0' || m.pricing.prompt === '0.0';
  const isVision = (m: ModelInfo) => {
    const modality = m.architecture?.modality;
    return typeof modality === 'string' && modality.includes('image');
  };

  const typeLabel = MODERATION_TYPES.find(t => t.key === moderationType)?.label || moderationType;

  return (
    <div className="space-y-4">
      <div className="card p-5">
        {/* Header */}
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-semibold text-gray-900">{typeLabel}</h2>
          <label className="flex items-center gap-2 cursor-pointer">
            <span className="text-sm text-gray-500">Enabled</span>
            <button
              onClick={() => setEnabled(!enabled)}
              className={`relative w-10 h-6 rounded-full transition-colors ${enabled ? 'bg-green-500' : 'bg-gray-300'}`}
            >
              <span className={`absolute top-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform ${enabled ? 'left-[18px]' : 'left-0.5'}`} />
            </button>
          </label>
        </div>

        {/* Engine Tabs — compact pill toggles */}
        <div className="flex items-center gap-1 p-1 bg-warm-100 rounded-lg mb-4">
          {ALL_ENGINES.map((eng) => {
            const active = engines.includes(eng.id);
            const isTab = activeTab === eng.id;
            const Icon = eng.icon;
            return (
              <div key={eng.id} className="flex-1 relative">
                <button
                  type="button"
                  onClick={() => {
                    if (active) setActiveTab(eng.id); // clicking active pill = switch view
                    else toggleEngine(eng.id);         // clicking inactive = enable + switch
                  }}
                  className={`w-full flex items-center justify-center gap-1.5 px-3 py-2 rounded-md text-xs font-semibold transition-all ${
                    active && isTab
                      ? 'bg-white text-gray-900 shadow-sm'
                      : active
                        ? 'bg-white/50 text-gray-600 hover:bg-white/70'
                        : 'text-gray-400 hover:text-gray-500'
                  }`}
                >
                  <Icon className="w-3.5 h-3.5" />
                  {eng.label}
                </button>
                {/* Active indicator dot */}
                {active && (
                  <span className="absolute -top-1 -right-1 w-2 h-2 bg-green-500 rounded-full border border-white" />
                )}
                {/* X button to disable */}
                {active && engines.length > 1 && (
                  <button
                    type="button"
                    onClick={(e) => { e.stopPropagation(); toggleEngine(eng.id); }}
                    className="absolute -top-1.5 -left-1 w-4 h-4 bg-red-400 hover:bg-red-500 text-white rounded-full flex items-center justify-center text-[9px] font-bold leading-none transition-colors"
                    title={`Disable ${eng.label}`}
                  >×</button>
                )}
              </div>
            );
          })}
        </div>

        {engines.length === 0 && (
          <div className="text-center py-4 text-sm text-red-500">Select at least one engine above</div>
        )}

        {/* ─── Local AI Config Panel ─── */}
        {activeTab === 'local_ai' && engines.includes('local_ai') && (
          <div className="rounded-lg border border-warm-200 p-4 mb-4 bg-warm-50/50">
            <div className="flex items-center gap-2 mb-3">
              <Cpu className="w-4 h-4 text-brand-600" />
              <span className="text-sm font-semibold text-gray-800">Local AI — On-Server Ollama</span>
              <span className="text-[10px] bg-green-100 text-green-700 px-1.5 py-0.5 rounded font-medium ml-auto">Free</span>
            </div>
            <p className="text-xs text-gray-500 mb-3">Runs locally on your server. No data leaves the machine. Select the model to use for this moderation type:</p>
            <select
              className="w-full text-sm border border-warm-300 rounded-lg px-3 py-2.5 bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              defaultValue="llama-guard3:1b"
            >
              {LOCAL_MODELS.map((lm) => (
                <option key={lm.id} value={lm.id}>
                  {lm.name} — {lm.desc}
                </option>
              ))}
            </select>
            <p className="text-[11px] text-gray-400 mt-2">LLaMA Guard 3 is recommended for moderation — fast (~1-2s) and purpose-built for safety classification.</p>
          </div>
        )}

        {/* ─── OpenRouter Config Panel ─── */}
        {activeTab === 'openrouter' && engines.includes('openrouter') && (
          <div className="rounded-lg border border-warm-200 p-4 mb-4 bg-warm-50/50">
            <div className="flex items-center gap-2 mb-3">
              <Cloud className="w-4 h-4 text-brand-600" />
              <span className="text-sm font-semibold text-gray-800">OpenRouter — Cloud Models</span>
              <span className="text-[10px] bg-amber-100 text-amber-700 px-1.5 py-0.5 rounded font-medium ml-auto">Paid / Free Tier</span>
            </div>

            {/* Model Dropdown */}
            <label className="text-xs font-medium text-gray-600 block mb-1">Model</label>
            <div
              onClick={() => setShowPicker(!showPicker)}
              className="flex items-center justify-between px-3 py-2.5 border border-warm-300 rounded-lg cursor-pointer hover:bg-white transition-colors bg-white mb-2"
            >
              {modelId ? (
                <div className="min-w-0">
                  <span className="text-sm font-medium text-gray-900">{modelName || modelId}</span>
                  <span className="text-xs text-gray-400 ml-2 font-mono">{modelId}</span>
                </div>
              ) : (
                <span className="text-sm text-gray-400">Click to select a model...</span>
              )}
              <ChevronDown className={`w-4 h-4 text-gray-400 transition-transform ${showPicker ? 'rotate-180' : ''}`} />
            </div>

            {/* Model Picker */}
            {showPicker && (
              <div className="mb-3 border border-warm-200 rounded-lg overflow-hidden">
                <div className="p-2.5 bg-warm-100 flex gap-2">
                  <div className="relative flex-1">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                    <input
                      type="text"
                      placeholder="Search models..."
                      value={searchTerm}
                      onChange={(e) => onSearchChange(e.target.value)}
                      className="w-full pl-9 pr-3 py-2 text-sm border border-warm-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500"
                    />
                  </div>
                  <select
                    value={capability}
                    onChange={(e) => onCapabilityChange(e.target.value)}
                    className="text-sm border border-warm-300 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
                  >
                    <option value="">All</option>
                    <option value="free">Free</option>
                    <option value="vision">Vision</option>
                  </select>
                </div>
                <div className="max-h-64 overflow-y-auto">
                  {modelsLoading ? (
                    <div className="p-4 text-center text-gray-400 text-sm flex items-center justify-center gap-2">
                      <Loader2 className="w-4 h-4 animate-spin" /> Loading...
                    </div>
                  ) : models.length === 0 ? (
                    <div className="p-4 text-center text-gray-400 text-sm">No models found</div>
                  ) : (
                    models.map((m) => (
                      <div
                        key={m.id}
                        onClick={() => selectModel(m)}
                        className={`px-3 py-2 border-b border-warm-100 cursor-pointer hover:bg-brand-50 transition-colors ${modelId === m.id ? 'bg-brand-50' : ''}`}
                      >
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-2 min-w-0">
                            {modelId === m.id && <Check className="w-3.5 h-3.5 text-brand-600 flex-shrink-0" />}
                            <div className="min-w-0">
                              <div className="text-sm font-medium text-gray-900 truncate">{m.name}</div>
                              <div className="text-[11px] text-gray-400 font-mono truncate">{m.id}</div>
                            </div>
                          </div>
                          <div className="flex items-center gap-1.5 flex-shrink-0 ml-2">
                            {isVision(m) && <span className="text-[10px] bg-purple-100 text-purple-700 px-1.5 py-0.5 rounded font-medium">Vision</span>}
                            {isFree(m) ? (
                              <span className="text-[10px] bg-green-100 text-green-700 px-1.5 py-0.5 rounded font-medium">Free</span>
                            ) : (
                              <span className="text-[10px] text-gray-400">${m.pricing.prompt}/tok</span>
                            )}
                            <span className="text-[10px] text-gray-300">{(m.context_length / 1000).toFixed(0)}k</span>
                          </div>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              </div>
            )}

            {/* System Prompt */}
            <label className="text-xs font-medium text-gray-600 block mb-1">
              System Prompt <span className="text-gray-400 font-normal">(leave blank for default)</span>
            </label>
            <textarea
              rows={4}
              value={systemPrompt}
              onChange={(e) => setSystemPrompt(e.target.value)}
              placeholder="Custom system prompt for this moderation type..."
              className="w-full text-sm border border-warm-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500 font-mono bg-white"
            />
          </div>
        )}

        {/* ─── OpenAI Config Panel ─── */}
        {activeTab === 'openai' && engines.includes('openai') && (
          <div className="rounded-lg border border-warm-200 p-4 mb-4 bg-warm-50/50">
            <div className="flex items-center gap-2 mb-3">
              <Server className="w-4 h-4 text-brand-600" />
              <span className="text-sm font-semibold text-gray-800">OpenAI Moderation — Three Poisons</span>
              <span className="text-[10px] bg-blue-100 text-blue-700 px-1.5 py-0.5 rounded font-medium ml-auto">Per-call</span>
            </div>
            <p className="text-xs text-gray-500 mb-2">OpenAI's moderation endpoint with Three Poisons scoring (Hate, Greed, Delusion). Automatically configured — no model selection needed.</p>
            <div className="flex gap-4 text-xs">
              <div className="flex items-center gap-1.5 text-gray-500">
                <span className="w-2 h-2 rounded-full bg-red-400" /> <strong>Hate</strong> — hate, harassment, violence, sexual
              </div>
              <div className="flex items-center gap-1.5 text-gray-500">
                <span className="w-2 h-2 rounded-full bg-amber-400" /> <strong>Greed</strong> — keyword fallback
              </div>
              <div className="flex items-center gap-1.5 text-gray-500">
                <span className="w-2 h-2 rounded-full bg-purple-400" /> <strong>Delusion</strong> — self-harm
              </div>
            </div>
          </div>
        )}

        {/* ─── Google Vision Config Panel ─── */}
        {activeTab === 'google' && engines.includes('google') && (
          <div className="rounded-lg border border-warm-200 p-4 mb-4 bg-warm-50/50">
            <div className="flex items-center gap-2 mb-3">
              <Eye className="w-4 h-4 text-brand-600" />
              <span className="text-sm font-semibold text-gray-800">Google Vision — SafeSearch</span>
              <span className="text-[10px] bg-blue-100 text-blue-700 px-1.5 py-0.5 rounded font-medium ml-auto">Per-call</span>
            </div>
            <p className="text-xs text-gray-500 mb-2">Google Cloud Vision SafeSearch API for image moderation. Detects adult, violence, racy, spoof, and medical content in images. Scores are mapped to Three Poisons.</p>
            <div className="flex gap-4 text-xs flex-wrap">
              <div className="flex items-center gap-1.5 text-gray-500">
                <span className="w-2 h-2 rounded-full bg-red-400" /> <strong>Adult + Violence + Racy</strong> → Hate
              </div>
              <div className="flex items-center gap-1.5 text-gray-500">
                <span className="w-2 h-2 rounded-full bg-purple-400" /> <strong>Medical</strong> → Delusion
              </div>
            </div>
            <p className="text-[11px] text-gray-400 mt-3">Configured via service account credentials. Image-only — text posts pass through without Google Vision analysis.</p>
          </div>
        )}

        {/* Save */}
        <div className="flex items-center justify-between">
          <div className="text-xs text-gray-400">
            {config?.updated_at && `Last updated: ${new Date(config.updated_at).toLocaleString()}`}
          </div>
          <button onClick={handleSave} disabled={saving || engines.length === 0} className="btn-primary text-sm flex items-center gap-1.5 disabled:opacity-40">
            <Sparkles className="w-4 h-4" /> {saving ? 'Saving...' : 'Save Configuration'}
          </button>
        </div>
      </div>

      {/* Test Panel */}
      <div className="card p-5">
        <h3 className="font-semibold text-gray-900 mb-3 flex items-center gap-2">
          <Play className="w-4 h-4" /> Test Moderation
        </h3>
        <p className="text-xs text-gray-400 mb-3">
          {moderationType.includes('image') || moderationType === 'video'
            ? 'Enter an image URL to test vision moderation'
            : 'Enter text content to test moderation'}
        </p>

        {/* Engine selector + input */}
        <div className="flex gap-2 mb-3">
          <select
            value={testEngine}
            onChange={(e) => setTestEngine(e.target.value)}
            className="text-sm border border-warm-300 rounded-lg px-2 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
          >
            {engines.map(e => (
              <option key={e} value={e}>
                {e === 'local_ai' ? 'Local AI' : e === 'openrouter' ? 'OpenRouter' : e === 'google' ? 'Google Vision' : 'OpenAI'}
              </option>
            ))}
          </select>
          <input
            type="text"
            value={testInput}
            onChange={(e) => setTestInput(e.target.value)}
            placeholder={moderationType.includes('image') || moderationType === 'video' ? 'Enter image URL...' : 'Enter test text...'}
            className="flex-1 text-sm border border-warm-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
          <button
            onClick={handleTest}
            disabled={testing || !enabled || engines.length === 0}
            className="btn-primary text-sm flex items-center gap-1.5 disabled:opacity-40"
          >
            {testing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Play className="w-4 h-4" />}
            Test
          </button>
        </div>

        {/* Full response display */}
        {testResponse && (
          <div className="space-y-3">
            {/* Meta bar: engine + type + input */}
            <div className="flex items-center gap-2 text-xs text-gray-500 bg-warm-50 rounded-lg p-2.5">
              <span className="font-semibold">Engine:</span>
              <span className="bg-brand-100 text-brand-700 px-1.5 py-0.5 rounded font-medium">
                {testResponse.engine === 'local_ai' ? 'Local AI' : testResponse.engine === 'openrouter' ? 'OpenRouter' : testResponse.engine === 'google' ? 'Google Vision' : 'OpenAI'}
              </span>
              <span className="text-gray-300">|</span>
              <span className="font-semibold">Type:</span> {testResponse.moderation_type}
              <span className="text-gray-300">|</span>
              <span className="font-semibold">Input:</span>
              <span className="text-gray-600 truncate max-w-[200px]" title={testResponse.input}>{testResponse.input}</span>
            </div>

            {/* Error display */}
            {testResponse.error && (
              <div className="bg-red-50 text-red-700 p-3 rounded-lg text-sm">
                <span className="font-semibold">Error:</span> {testResponse.error}
              </div>
            )}

            {/* Result display */}
            {testResponse.result && (
              <div className={`p-4 rounded-lg text-sm ${
                testResponse.result.action === 'flag' ? 'bg-red-50' :
                testResponse.result.action === 'nsfw' ? 'bg-amber-50' : 'bg-green-50'
              }`}>
                <div className="space-y-3">
                  {/* Verdict */}
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className={`text-lg font-bold ${
                      testResponse.result.action === 'flag' ? 'text-red-700' :
                      testResponse.result.action === 'nsfw' ? 'text-amber-700' : 'text-green-700'
                    }`}>
                      {testResponse.result.action === 'flag' ? '⛔ FLAGGED' :
                       testResponse.result.action === 'nsfw' ? '⚠️ NSFW' : '✅ CLEAN'}
                    </span>
                    {testResponse.result.nsfw_reason && (
                      <span className="text-xs font-medium bg-amber-200 text-amber-800 px-2 py-0.5 rounded-full">{testResponse.result.nsfw_reason}</span>
                    )}
                    {testResponse.result.reason && <span className="text-gray-600">— {testResponse.result.reason}</span>}
                  </div>

                  {/* Explanation */}
                  {testResponse.result.explanation && (
                    <div className="bg-white/60 rounded-lg p-3 border border-warm-200">
                      <p className="text-xs font-semibold text-gray-500 uppercase mb-1">AI Analysis</p>
                      <p className="text-sm text-gray-700 leading-relaxed">{testResponse.result.explanation}</p>
                    </div>
                  )}

                  {/* Categories (for local AI) */}
                  {testResponse.result.categories && testResponse.result.categories.length > 0 && (
                    <div className="flex gap-1.5 flex-wrap">
                      {testResponse.result.categories.map((cat: string, i: number) => (
                        <span key={i} className="text-xs font-medium bg-red-100 text-red-700 px-2 py-0.5 rounded">{cat}</span>
                      ))}
                    </div>
                  )}

                  {/* Score Bars (for OpenRouter/OpenAI) */}
                  {(testResponse.result.hate !== undefined || testResponse.result.greed !== undefined) && (
                    <div className="space-y-2">
                      <ScoreBarDetailed label="Hate" value={testResponse.result.hate} detail={testResponse.result.hate_detail} />
                      <ScoreBarDetailed label="Greed" value={testResponse.result.greed} detail={testResponse.result.greed_detail} />
                      <ScoreBarDetailed label="Delusion" value={testResponse.result.delusion} detail={testResponse.result.delusion_detail} />
                    </div>
                  )}

                  {/* Raw response — always visible */}
                  {testResponse.result.raw_content && (
                    <div className="mt-2">
                      <p className="text-xs font-semibold text-gray-500 uppercase mb-1">Raw Response</p>
                      <pre className="text-xs bg-white p-2.5 rounded border border-warm-200 overflow-x-auto whitespace-pre-wrap font-mono text-gray-700">{testResponse.result.raw_content}</pre>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* Full JSON dump for debugging */}
            <details>
              <summary className="text-xs text-gray-400 cursor-pointer">Full JSON response</summary>
              <pre className="mt-1 text-xs bg-gray-50 p-2.5 rounded border border-warm-200 overflow-x-auto whitespace-pre-wrap font-mono text-gray-600">
                {JSON.stringify(testResponse, null, 2)}
              </pre>
            </details>
          </div>
        )}
      </div>
    </div>
  );
}

function ScoreBarDetailed({ label, value, detail }: { label: string; value: number; detail?: string }) {
  const pct = Math.round((value || 0) * 100);
  const color = pct > 50 ? 'bg-red-500' : pct > 25 ? 'bg-amber-400' : 'bg-green-400';
  const textColor = pct > 50 ? 'text-red-700' : pct > 25 ? 'text-amber-700' : 'text-green-700';
  return (
    <div className="bg-white/50 rounded-lg p-2.5 border border-warm-100">
      <div className="flex justify-between text-xs mb-1">
        <span className="font-semibold text-gray-700">{label}</span>
        <span className={`font-mono font-bold ${textColor}`}>{pct}%</span>
      </div>
      <div className="h-1.5 bg-gray-200 rounded-full overflow-hidden mb-1.5">
        <div className={`h-full ${color} rounded-full transition-all`} style={{ width: `${pct}%` }} />
      </div>
      {detail && <p className="text-xs text-gray-500 leading-relaxed">{detail}</p>}
    </div>
  );
}
