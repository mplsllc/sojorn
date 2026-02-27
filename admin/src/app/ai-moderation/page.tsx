// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { useEffect, useState, useCallback } from 'react';
import { Brain, Play, Loader2, Eye, MessageSquare, Video, Shield, MapPin, Users, AlertTriangle, Cpu, Terminal, Upload, Sliders, ChevronDown, ChevronRight } from 'lucide-react';

const MODERATION_TYPES = [
  { key: 'text', label: 'Text Moderation', icon: MessageSquare },
  { key: 'image', label: 'Image Moderation', icon: Eye },
  { key: 'video', label: 'Video Moderation', icon: Video },
  { key: 'group_text', label: 'Group Chat', icon: Users },
  { key: 'group_image', label: 'Group Image', icon: Shield },
  { key: 'beacon_text', label: 'Beacon Text', icon: MapPin },
  { key: 'beacon_image', label: 'Beacon Image', icon: AlertTriangle },
];

const ENGINES = [
  { id: 'local_ai', label: 'Local AI (Ollama)', icon: Cpu },
  { id: 'sightengine', label: 'SightEngine', icon: Shield },
];

// SightEngine image moderation models
const SE_IMAGE_MODELS = [
  { key: 'nudity', label: 'Nudity & Adult Content', desc: 'Sexual activity, nudity, suggestive content (29 sub-classes)', category: 'safety' },
  { key: 'gore', label: 'Gore & Disgusting', desc: 'Blood, corpses, injuries, body waste', category: 'safety' },
  { key: 'violence', label: 'Violence', desc: 'Physical violence, firearm threats, combat', category: 'safety' },
  { key: 'weapon', label: 'Weapons', desc: 'Firearms, knives, toy guns, gun gestures', category: 'safety' },
  { key: 'offensive', label: 'Hate & Offensive', desc: 'Nazi symbols, confederate flags, supremacist imagery, middle finger', category: 'safety' },
  { key: 'self-harm', label: 'Self-Harm', desc: 'Cutting, self-injury, scars (beta)', category: 'safety' },
  { key: 'recreational_drug', label: 'Recreational Drugs', desc: 'Cannabis, cocaine, syringes, drug paraphernalia', category: 'restricted' },
  { key: 'medical', label: 'Medical Drugs', desc: 'Pills, medical syringes, paraphernalia', category: 'restricted' },
  { key: 'alcohol', label: 'Alcohol', desc: 'Beer, wine, cocktails, spirits, bar scenes', category: 'restricted' },
  { key: 'tobacco', label: 'Tobacco & Smoking', desc: 'Cigarettes, cigars, vapes, hookah', category: 'restricted' },
  { key: 'gambling', label: 'Gambling', desc: 'Casinos, slot machines, poker chips, lottery', category: 'restricted' },
  { key: 'money', label: 'Money & Cash', desc: 'Banknotes, currency displays', category: 'restricted' },
  { key: 'destruction', label: 'Destruction & Fire', desc: 'Building damage, vehicle fires, wildfires, violent protests', category: 'sensitive' },
  { key: 'military', label: 'Military', desc: 'Military vehicles, personnel, equipment', category: 'sensitive' },
  { key: 'genai', label: 'AI-Generated Detection', desc: 'Stable Diffusion, MidJourney, DALL-E, Flux', category: 'analysis' },
  { key: 'text-content', label: 'Text in Images (OCR)', desc: 'Profanity, PII, links, extremism in embedded text', category: 'analysis' },
  { key: 'qr-content', label: 'QR Code Moderation', desc: 'Scan QR codes for malicious URLs, profanity, PII', category: 'analysis' },
];

// SightEngine text ML classification classes
const SE_TEXT_MODELS = [
  { key: 'sexual', label: 'Sexual', desc: 'Sexual acts, organs, sexually associated content' },
  { key: 'discriminatory', label: 'Discriminatory', desc: 'Hate speech targeting identity characteristics' },
  { key: 'insulting', label: 'Insulting', desc: 'Disrespectful, dignity-undermining language' },
  { key: 'violent', label: 'Violent', desc: 'Threatening or brutal content' },
  { key: 'toxic', label: 'Toxic', desc: 'Generally unacceptable, harmful, offensive' },
  { key: 'self-harm', label: 'Self-Harm', desc: 'References to self-harm or suicide' },
];

// SightEngine text rule-based categories
const SE_TEXT_CATEGORIES = [
  { key: 'profanity', label: 'Profanity', desc: 'Sexual, discriminatory, insulting language' },
  { key: 'personal', label: 'Personal Info (PII)', desc: 'Email, phone, SSN, usernames, IP addresses' },
  { key: 'link', label: 'Links & URLs', desc: 'External URLs and domains' },
  { key: 'extremism', label: 'Extremism', desc: 'Extremist ideologies and related terms' },
  { key: 'weapon', label: 'Weapon Terms', desc: 'Firearms terminology' },
  { key: 'drug', label: 'Drug Terms', desc: 'Recreational drug terminology' },
  { key: 'self-harm', label: 'Self-Harm Terms', desc: 'Suicide and self-injury references' },
  { key: 'violence', label: 'Violence Terms', desc: 'Threats and harmful expressions' },
  { key: 'spam', label: 'Spam', desc: 'Spam indicators and circumvention attempts' },
  { key: 'content-trade', label: 'Content Trading', desc: 'Requests to exchange intimate content' },
  { key: 'money-transaction', label: 'Money Requests', desc: 'Requests for financial transfers' },
];

const CATEGORY_LABELS: Record<string, string> = {
  safety: 'Safety & Harm',
  restricted: 'Restricted Content',
  sensitive: 'Sensitive Topics',
  analysis: 'Content Analysis',
};

interface ModerationConfig {
  id: string;
  moderation_type: string;
  model_id: string;
  model_name: string;
  system_prompt: string;
  enabled: boolean;
  engines: string[];
  sightengine_config: any;
  updated_at: string;
}

interface EngineInfo {
  id: string;
  name: string;
  status: string;
}

const defaultSEConfig = () => ({
  image_models: Object.fromEntries(
    SE_IMAGE_MODELS.map(m => [m.key, { enabled: ['nudity', 'gore', 'violence', 'weapon', 'offensive', 'self-harm', 'recreational_drug', 'medical'].includes(m.key), threshold: 0.7 }])
  ),
  text_models: Object.fromEntries(
    SE_TEXT_MODELS.map(m => [m.key, { enabled: true, threshold: 0.7 }])
  ),
  text_categories: Object.fromEntries(
    SE_TEXT_CATEGORIES.map(c => [c.key, ['profanity', 'personal', 'link', 'extremism', 'self-harm', 'violence', 'spam', 'content-trade', 'money-transaction'].includes(c.key)])
  ),
  nsfw_threshold: 0.4,
  flag_threshold: 0.7,
});

export default function AIModerationPage() {
  const [configs, setConfigs] = useState<ModerationConfig[]>([]);
  const [engines, setEngines] = useState<EngineInfo[]>([]);
  const [loading, setLoading] = useState(true);

  const [selectedType, setSelectedType] = useState('text');
  const [selectedEngine, setSelectedEngine] = useState('local_ai');

  const [enabled, setEnabled] = useState(false);
  const [modelId, setModelId] = useState('');
  const [modelName, setModelName] = useState('');
  const [systemPrompt, setSystemPrompt] = useState('');
  const [seConfig, setSEConfig] = useState<any>(defaultSEConfig());
  const [saving, setSaving] = useState(false);
  const [isDirty, setIsDirty] = useState(false);

  const [testInput, setTestInput] = useState('');
  const [testing, setTesting] = useState(false);
  const [testHistory, setTestHistory] = useState<any[]>([]);
  const [uploadedFile, setUploadedFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [localModels, setLocalModels] = useState<{id: string; name: string}[]>([]);

  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(new Set(['safety']));

  const loadConfigs = useCallback(() => {
    setLoading(true);
    Promise.all([
      api.getAIModerationConfigs(),
      api.getAIEngines(),
      api.listLocalModels()
    ])
      .then(([configData, engineData, modelData]) => {
        setConfigs(configData.configs || []);
        setEngines(engineData.engines || []);
        setLocalModels((modelData.models || []).map((m: any) => ({ id: m.id || m.name, name: m.name })));
      })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => { loadConfigs(); }, [loadConfigs]);

  useEffect(() => {
    const config = configs.find(c => c.moderation_type === selectedType);
    if (config) {
      setEnabled(config.enabled);
      setModelId(config.model_id || '');
      setModelName(config.model_name || '');
      setSystemPrompt(config.system_prompt || '');
      if (config.engines && config.engines.length > 0) {
        setSelectedEngine(config.engines[0]);
      }
      const sec = config.sightengine_config;
      if (sec && Object.keys(sec).length > 0) {
        setSEConfig({ ...defaultSEConfig(), ...sec });
      } else {
        setSEConfig(defaultSEConfig());
      }
    } else {
      setEnabled(false);
      setModelId('');
      setModelName('');
      setSystemPrompt('');
      setSEConfig(defaultSEConfig());
    }
    setIsDirty(false); // switching type discards unsaved state
  }, [selectedType, configs]);

  const handleSave = async () => {
    setSaving(true);
    try {
      await api.setAIModerationConfig({
        moderation_type: selectedType,
        model_id: modelId,
        model_name: modelName,
        system_prompt: systemPrompt,
        enabled,
        engines: [selectedEngine],
        sightengine_config: seConfig,
      });
      setIsDirty(false);
      loadConfigs();
    } catch (e: any) {
      alert(e.message);
    } finally {
      setSaving(false);
    }
  };

  const handleFileUpload = async (file: File) => {
    setUploading(true);
    try {
      const result = await api.uploadTestImage(file);
      setTestInput(result.url);
      setUploadedFile(file);
    } catch (e: any) {
      alert('Upload failed: ' + e.message);
    } finally {
      setUploading(false);
    }
  };

  const handleTest = async () => {
    if (!testInput.trim() && !uploadedFile) return;
    setTesting(true);
    const startTime = Date.now();
    try {
      const isImage = selectedType.includes('image') || selectedType === 'video';
      const data: any = { moderation_type: selectedType, engine: selectedEngine };
      if (isImage) {
        data.image_url = testInput;
      } else {
        data.content = testInput;
      }
      const res = await api.testAIModeration(data);
      const duration = Date.now() - startTime;
      const entry = { ...res, timestamp: new Date().toISOString(), duration };
      setTestHistory(prev => [entry, ...prev].slice(0, 10));
    } catch (e: any) {
      setTestHistory(prev => [{
        error: e.message, engine: selectedEngine, moderation_type: selectedType,
        timestamp: new Date().toISOString(), duration: Date.now() - startTime
      }, ...prev].slice(0, 10));
    } finally {
      setTesting(false);
    }
  };

  const updateImageModel = (key: string, field: 'enabled' | 'threshold', value: any) => {
    setSEConfig((prev: any) => ({
      ...prev,
      image_models: {
        ...prev.image_models,
        [key]: { ...prev.image_models?.[key], [field]: value },
      },
    }));
    setIsDirty(true);
  };

  const updateTextModel = (key: string, field: 'enabled' | 'threshold', value: any) => {
    setSEConfig((prev: any) => ({
      ...prev,
      text_models: {
        ...prev.text_models,
        [key]: { ...prev.text_models?.[key], [field]: value },
      },
    }));
    setIsDirty(true);
  };

  const updateTextCategory = (key: string, value: boolean) => {
    setSEConfig((prev: any) => ({
      ...prev,
      text_categories: { ...prev.text_categories, [key]: value },
    }));
    setIsDirty(true);
  };

  const toggleCategory = (cat: string) => {
    setExpandedCategories(prev => {
      const next = new Set(prev);
      if (next.has(cat)) next.delete(cat); else next.add(cat);
      return next;
    });
  };

  const typeLabel = MODERATION_TYPES.find(t => t.key === selectedType)?.label || selectedType;
  const engineLabel = ENGINES.find(e => e.id === selectedEngine)?.label || selectedEngine;
  const isImageType = selectedType.includes('image') || selectedType === 'video';
  const isTextType = selectedType.includes('text');

  const getEngineStatus = (id: string) => {
    const engine = engines.find(e => e.id === id);
    if (!engine) return { color: 'text-gray-400', dot: 'bg-gray-300', label: 'Unknown' };
    if (engine.status === 'ready') return { color: 'text-green-600', dot: 'bg-green-500', label: 'Online' };
    if (engine.status === 'down') return { color: 'text-red-600', dot: 'bg-red-500', label: 'Down' };
    return { color: 'text-gray-400', dot: 'bg-gray-300', label: 'Not Configured' };
  };

  const enabledImageCount = SE_IMAGE_MODELS.filter(m => seConfig.image_models?.[m.key]?.enabled).length;
  const enabledTextCount = SE_TEXT_MODELS.filter(m => seConfig.text_models?.[m.key]?.enabled).length;

  return (
    <AdminOnlyGuard>
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
          <Brain className="w-6 h-6" /> AI Moderation
        </h1>
        <p className="text-sm text-gray-500 mt-1">Configure AI moderation engines and SightEngine models</p>
      </div>

      {/* Engine Status */}
      <div className="card p-4 mb-4">
        <div className="flex items-center gap-4 text-sm">
          <span className="font-semibold text-gray-700">Engine Status:</span>
          {ENGINES.map(eng => {
            const status = getEngineStatus(eng.id);
            return (
              <div key={eng.id} className="flex items-center gap-1.5">
                <span className={`w-2 h-2 rounded-full ${status.dot}`} />
                <span className={status.color}>{eng.label}</span>
              </div>
            );
          })}
        </div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
        {/* Left Column: General Config */}
        <div className="space-y-4">
          <div className="card p-4">
            <label className="text-sm font-semibold text-gray-700 block mb-2">Moderation Type</label>
            <select
              value={selectedType}
              onChange={(e) => setSelectedType(e.target.value)}
              className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              {MODERATION_TYPES.map(t => (
                <option key={t.key} value={t.key}>{t.label}</option>
              ))}
            </select>
          </div>

          <div className="card p-4">
            <label className="text-sm font-semibold text-gray-700 block mb-2">Engine</label>
            <select
              value={selectedEngine}
              onChange={(e) => { setSelectedEngine(e.target.value); setIsDirty(true); }}
              className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              {ENGINES.map(e => (
                <option key={e.id} value={e.id}>{e.label}</option>
              ))}
            </select>
          </div>

          <div className="card p-4">
            <label className="text-sm font-semibold text-gray-700 block mb-2">Moderation Instructions</label>
            <p className="text-xs text-gray-500 mb-2">
              Guidelines for the AI when moderating {typeLabel.toLowerCase()} content.
            </p>
            <textarea
              rows={4}
              value={systemPrompt}
              onChange={(e) => { setSystemPrompt(e.target.value); setIsDirty(true); }}
              placeholder="Flag content that promotes violence, hate speech, or illegal activities..."
              className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>

          {selectedEngine === 'local_ai' && (
            <div className="card p-4">
              <h3 className="text-sm font-semibold text-gray-700 mb-2">Local AI Model</h3>
              <select
                value={modelId}
                onChange={(e) => {
                  const selected = localModels.find(m => m.id === e.target.value);
                  setModelId(e.target.value);
                  setModelName(selected?.name || '');
                  setIsDirty(true);
                }}
                className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
              >
                <option value="">Select model...</option>
                {localModels.map(m => (
                  <option key={m.id} value={m.id}>{m.name}</option>
                ))}
              </select>
            </div>
          )}

          {/* Global Thresholds */}
          {selectedEngine === 'sightengine' && (
            <div className="card p-4">
              <h3 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
                <Sliders className="w-4 h-4" /> Global Thresholds
              </h3>
              <div className="space-y-3">
                <div>
                  <div className="flex items-center justify-between mb-1">
                    <label className="text-xs font-medium text-gray-600">Flag Threshold</label>
                    <span className="text-xs font-mono text-gray-500">{(seConfig.flag_threshold ?? 0.7).toFixed(2)}</span>
                  </div>
                  <input
                    type="range"
                    min="0.1" max="1.0" step="0.05"
                    value={seConfig.flag_threshold ?? 0.7}
                    onChange={(e) => { setSEConfig((p: any) => ({ ...p, flag_threshold: parseFloat(e.target.value) })); setIsDirty(true); }}
                    className="w-full h-1.5 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-red-500"
                  />
                  <p className="text-[10px] text-gray-400 mt-0.5">Content above this score is flagged for review</p>
                </div>
                <div>
                  <div className="flex items-center justify-between mb-1">
                    <label className="text-xs font-medium text-gray-600">NSFW Threshold</label>
                    <span className="text-xs font-mono text-gray-500">{(seConfig.nsfw_threshold ?? 0.4).toFixed(2)}</span>
                  </div>
                  <input
                    type="range"
                    min="0.1" max="1.0" step="0.05"
                    value={seConfig.nsfw_threshold ?? 0.4}
                    onChange={(e) => { setSEConfig((p: any) => ({ ...p, nsfw_threshold: parseFloat(e.target.value) })); setIsDirty(true); }}
                    className="w-full h-1.5 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-amber-500"
                  />
                  <p className="text-[10px] text-gray-400 mt-0.5">Content above this score is blurred as NSFW</p>
                </div>
              </div>
            </div>
          )}

          {/* Save */}
          <div className="card p-4 flex items-center justify-between">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={enabled}
                onChange={(e) => { setEnabled(e.target.checked); setIsDirty(true); }}
                className="w-4 h-4 text-brand-600 rounded focus:ring-2 focus:ring-brand-500"
              />
              <span className="text-sm font-medium text-gray-700">Enable {typeLabel}</span>
            </label>
            <div className="flex items-center gap-2">
              {isDirty && (
                <span className="text-xs font-medium text-amber-600 bg-amber-50 border border-amber-200 px-2 py-1 rounded">
                  Unsaved changes
                </span>
              )}
              <button
                type="button"
                onClick={handleSave}
                disabled={saving}
                className="btn-primary text-sm disabled:opacity-40"
              >
                {saving ? 'Saving...' : 'Save Configuration'}
              </button>
            </div>
          </div>
        </div>

        {/* Middle Column: SightEngine Model Config */}
        <div className="space-y-4">
          {selectedEngine === 'sightengine' && isImageType && (
            <div className="card p-4">
              <h3 className="text-sm font-semibold text-gray-700 mb-1 flex items-center gap-2">
                <Eye className="w-4 h-4" /> Image Models
                <span className="text-xs font-normal text-gray-400 ml-auto">{enabledImageCount}/{SE_IMAGE_MODELS.length} active</span>
              </h3>
              <p className="text-[10px] text-gray-400 mb-3">Select which visual checks to run. Each enabled model counts toward your SightEngine API usage.</p>

              {Object.entries(CATEGORY_LABELS).map(([catKey, catLabel]) => {
                const models = SE_IMAGE_MODELS.filter(m => m.category === catKey);
                const expanded = expandedCategories.has(catKey);
                const enabledInCat = models.filter(m => seConfig.image_models?.[m.key]?.enabled).length;
                return (
                  <div key={catKey} className="mb-2">
                    <button
                      onClick={() => toggleCategory(catKey)}
                      className="w-full flex items-center justify-between py-1.5 px-2 rounded hover:bg-gray-50 text-left"
                    >
                      <span className="text-xs font-semibold text-gray-600">{catLabel}</span>
                      <span className="flex items-center gap-1.5">
                        <span className="text-[10px] text-gray-400">{enabledInCat}/{models.length}</span>
                        {expanded ? <ChevronDown className="w-3.5 h-3.5 text-gray-400" /> : <ChevronRight className="w-3.5 h-3.5 text-gray-400" />}
                      </span>
                    </button>
                    {expanded && (
                      <div className="space-y-1 mt-1">
                        {models.map(m => {
                          const mc = seConfig.image_models?.[m.key] || { enabled: false, threshold: 0.7 };
                          return (
                            <div key={m.key} className={`rounded-lg border px-3 py-2 ${mc.enabled ? 'border-brand-200 bg-brand-50/30' : 'border-gray-100 bg-gray-50/50'}`}>
                              <div className="flex items-center gap-2">
                                <input
                                  type="checkbox"
                                  checked={mc.enabled}
                                  onChange={(e) => updateImageModel(m.key, 'enabled', e.target.checked)}
                                  className="w-3.5 h-3.5 text-brand-600 rounded focus:ring-1 focus:ring-brand-500"
                                />
                                <div className="flex-1 min-w-0">
                                  <div className="text-xs font-medium text-gray-800">{m.label}</div>
                                  <div className="text-[10px] text-gray-400 truncate">{m.desc}</div>
                                </div>
                              </div>
                              {mc.enabled && (
                                <div className="flex items-center gap-2 mt-1.5 ml-5">
                                  <input
                                    type="range"
                                    min="0.1" max="1.0" step="0.05"
                                    value={mc.threshold}
                                    onChange={(e) => updateImageModel(m.key, 'threshold', parseFloat(e.target.value))}
                                    className="flex-1 h-1 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-brand-500"
                                  />
                                  <span className="text-[10px] font-mono text-gray-500 w-8 text-right">{mc.threshold.toFixed(2)}</span>
                                </div>
                              )}
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}

          {selectedEngine === 'sightengine' && isTextType && (
            <>
              <div className="card p-4">
                <h3 className="text-sm font-semibold text-gray-700 mb-1 flex items-center gap-2">
                  <MessageSquare className="w-4 h-4" /> Text ML Classification
                  <span className="text-xs font-normal text-gray-400 ml-auto">{enabledTextCount}/{SE_TEXT_MODELS.length} active</span>
                </h3>
                <p className="text-[10px] text-gray-400 mb-3">ML-based text classification. Returns confidence scores per class.</p>
                <div className="space-y-1">
                  {SE_TEXT_MODELS.map(m => {
                    const mc = seConfig.text_models?.[m.key] || { enabled: true, threshold: 0.7 };
                    return (
                      <div key={m.key} className={`rounded-lg border px-3 py-2 ${mc.enabled ? 'border-brand-200 bg-brand-50/30' : 'border-gray-100 bg-gray-50/50'}`}>
                        <div className="flex items-center gap-2">
                          <input
                            type="checkbox"
                            checked={mc.enabled}
                            onChange={(e) => updateTextModel(m.key, 'enabled', e.target.checked)}
                            className="w-3.5 h-3.5 text-brand-600 rounded focus:ring-1 focus:ring-brand-500"
                          />
                          <div className="flex-1 min-w-0">
                            <div className="text-xs font-medium text-gray-800">{m.label}</div>
                            <div className="text-[10px] text-gray-400">{m.desc}</div>
                          </div>
                        </div>
                        {mc.enabled && (
                          <div className="flex items-center gap-2 mt-1.5 ml-5">
                            <input
                              type="range"
                              min="0.1" max="1.0" step="0.05"
                              value={mc.threshold}
                              onChange={(e) => updateTextModel(m.key, 'threshold', parseFloat(e.target.value))}
                              className="flex-1 h-1 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-brand-500"
                            />
                            <span className="text-[10px] font-mono text-gray-500 w-8 text-right">{mc.threshold.toFixed(2)}</span>
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>

              <div className="card p-4">
                <h3 className="text-sm font-semibold text-gray-700 mb-1 flex items-center gap-2">
                  <Shield className="w-4 h-4" /> Rule-Based Text Categories
                </h3>
                <p className="text-[10px] text-gray-400 mb-3">Pattern-matching categories (profanity, PII, links, etc.)</p>
                <div className="space-y-1">
                  {SE_TEXT_CATEGORIES.map(c => {
                    const on = seConfig.text_categories?.[c.key] ?? false;
                    return (
                      <label key={c.key} className={`flex items-center gap-2 rounded-lg border px-3 py-2 cursor-pointer ${on ? 'border-brand-200 bg-brand-50/30' : 'border-gray-100 bg-gray-50/50'}`}>
                        <input
                          type="checkbox"
                          checked={on}
                          onChange={(e) => updateTextCategory(c.key, e.target.checked)}
                          className="w-3.5 h-3.5 text-brand-600 rounded focus:ring-1 focus:ring-brand-500"
                        />
                        <div className="flex-1 min-w-0">
                          <div className="text-xs font-medium text-gray-800">{c.label}</div>
                          <div className="text-[10px] text-gray-400">{c.desc}</div>
                        </div>
                      </label>
                    );
                  })}
                </div>
              </div>
            </>
          )}

          {selectedEngine !== 'sightengine' && (
            <div className="card p-4">
              <p className="text-sm text-gray-500">Select the <strong>SightEngine</strong> engine to configure visual and text moderation models.</p>
            </div>
          )}

          {selectedEngine === 'sightengine' && !isImageType && !isTextType && (
            <div className="card p-4">
              <p className="text-sm text-gray-500">Select an image or text moderation type to configure SightEngine models.</p>
            </div>
          )}
        </div>

        {/* Right Column: Test Terminal */}
        <div className="space-y-4">
          <div className="card p-4">
            <h3 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
              <Play className="w-4 h-4" /> Test Moderation
            </h3>

            {(isImageType) ? (
              <div className="space-y-3">
                <div className="flex gap-2">
                  <label className="flex-1">
                    <input
                      type="file"
                      accept="image/*"
                      onChange={(e) => {
                        const file = e.target.files?.[0];
                        if (file) handleFileUpload(file);
                      }}
                      className="hidden"
                    />
                    <div className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 cursor-pointer hover:bg-gray-50 flex items-center justify-center gap-2">
                      <Upload className="w-4 h-4" />
                      {uploading ? 'Uploading...' : (uploadedFile ? `Uploaded: ${uploadedFile.name}` : 'Click to upload image...')}
                    </div>
                  </label>
                </div>
                <div className="text-xs text-gray-500 text-center">OR</div>
                <input
                  type="text"
                  value={testInput}
                  onChange={(e) => setTestInput(e.target.value)}
                  placeholder="Image URL..."
                  className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
                  onKeyDown={(e) => e.key === 'Enter' && handleTest()}
                />
              </div>
            ) : (
              <input
                type="text"
                value={testInput}
                onChange={(e) => setTestInput(e.target.value)}
                placeholder="Test text..."
                className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
                onKeyDown={(e) => e.key === 'Enter' && handleTest()}
              />
            )}

            <div className="flex gap-2 mt-3">
              <button
                onClick={handleTest}
                disabled={testing || (!testInput.trim() && !uploadedFile)}
                className="btn-primary text-sm flex items-center gap-1.5 disabled:opacity-40"
              >
                {testing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Play className="w-4 h-4" />}
                Test
              </button>
              {uploadedFile && (
                <button
                  onClick={() => { setUploadedFile(null); setTestInput(''); }}
                  className="text-sm text-gray-500 hover:text-gray-700"
                >
                  Clear
                </button>
              )}
            </div>
          </div>

          {/* Terminal */}
          <div className="card p-0 overflow-hidden">
            <div className="bg-gray-900 px-4 py-2 flex items-center gap-2 border-b border-gray-700">
              <Terminal className="w-4 h-4 text-green-400" />
              <span className="text-xs font-mono text-green-400">moderation-test</span>
            </div>
            <div className="bg-gray-950 p-4 font-mono text-xs text-green-400 h-[600px] overflow-y-auto">
              {testHistory.length === 0 ? (
                <div className="text-gray-600">Waiting for test input...</div>
              ) : (
                <div className="space-y-4">
                  {testHistory.map((entry, idx) => (
                    <div key={idx} className="border-b border-gray-800 pb-3 last:border-0">
                      <div className="text-gray-500 mb-1">
                        [{new Date(entry.timestamp).toLocaleTimeString()}] {entry.engine} &bull; {entry.moderation_type} &bull; {entry.duration}ms
                      </div>
                      {entry.error ? (
                        <div className="text-red-400">ERROR: {entry.error}</div>
                      ) : entry.result ? (
                        <div className="space-y-1">
                          <div className={entry.result.flagged ? 'text-red-400' : 'text-green-400'}>
                            {entry.result.flagged ? 'FLAGGED' : 'CLEAN'}
                            {entry.result.reason && `: ${entry.result.reason}`}
                          </div>
                          {entry.result.explanation && (
                            <div className="text-gray-400 pl-4">{entry.result.explanation}</div>
                          )}
                          {entry.result.hate !== undefined && (
                            <div className="text-gray-400 pl-4">
                              Hate: {(entry.result.hate * 100).toFixed(1)}% |
                              Greed: {(entry.result.greed * 100).toFixed(1)}% |
                              Delusion: {(entry.result.delusion * 100).toFixed(1)}%
                            </div>
                          )}
                          {entry.result.categories && entry.result.categories.length > 0 && (
                            <div className="text-yellow-400 pl-4">
                              Categories: {entry.result.categories.join(', ')}
                            </div>
                          )}
                        </div>
                      ) : null}
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </AdminShell>
    </AdminOnlyGuard>
  );
}
