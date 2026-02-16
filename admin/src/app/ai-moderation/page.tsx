'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useEffect, useState, useCallback, useRef } from 'react';
import { Brain, Search, Check, ChevronDown, Play, Loader2, Eye, MessageSquare, Video, Shield, MapPin, Users, AlertTriangle, Server, Cloud, Cpu, Terminal, Upload } from 'lucide-react';

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
  { id: 'openrouter', label: 'OpenRouter', icon: Cloud },
  { id: 'openai', label: 'OpenAI', icon: Server },
  { id: 'google', label: 'Google Vision', icon: Eye },
  { id: 'azure', label: 'Azure OpenAI', icon: Cloud },
];

const LOCAL_MODELS = [
  { id: 'llama-guard3:1b', name: 'LLaMA Guard 3 (1B)' },
  { id: 'qwen2.5:7b-instruct-q4_K_M', name: 'Qwen 2.5 (7B)' },
];

interface ModelInfo {
  id: string;
  name: string;
  pricing: { prompt: string; completion: string };
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

interface EngineInfo {
  id: string;
  name: string;
  status: string;
}

export default function AIModerationPage() {
  const [configs, setConfigs] = useState<ModerationConfig[]>([]);
  const [engines, setEngines] = useState<EngineInfo[]>([]);
  const [loading, setLoading] = useState(true);
  
  // Selection states
  const [selectedType, setSelectedType] = useState('text');
  const [selectedEngine, setSelectedEngine] = useState('local_ai');
  
  // Config states
  const [enabled, setEnabled] = useState(false);
  const [modelId, setModelId] = useState('');
  const [modelName, setModelName] = useState('');
  const [systemPrompt, setSystemPrompt] = useState('');
  const [saving, setSaving] = useState(false);
  
  // OpenRouter model picker
  const [showPicker, setShowPicker] = useState(false);
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [modelsLoading, setModelsLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  
  // Test states
  const [testInput, setTestInput] = useState('');
  const [testResponse, setTestResponse] = useState<any>(null);
  const [testing, setTesting] = useState(false);
  const [testHistory, setTestHistory] = useState<any[]>([]);
  const [uploadedFile, setUploadedFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);

  const loadConfigs = useCallback(() => {
    setLoading(true);
    Promise.all([
      api.getAIModerationConfigs(),
      api.getAIEngines()
    ])
      .then(([configData, engineData]) => {
        setConfigs(configData.configs || []);
        setEngines(engineData.engines || []);
      })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => { loadConfigs(); }, [loadConfigs]);

  // Load config when type changes
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
    } else {
      setEnabled(false);
      setModelId('');
      setModelName('');
      setSystemPrompt('');
    }
  }, [selectedType, configs]);

  const loadModels = useCallback((search?: string) => {
    setModelsLoading(true);
    api.listOpenRouterModels({ search })
      .then((data) => setModels(data.models || []))
      .finally(() => setModelsLoading(false));
  }, []);

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
      });
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
      // Create FormData and upload to get a URL
      const formData = new FormData();
      formData.append('file', file);
      
      const response = await fetch('/api/v1/admin/upload-test-image', {
        method: 'POST',
        body: formData,
      });
      
      if (!response.ok) {
        throw new Error('Upload failed');
      }
      
      const result = await response.json();
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
      const data = {
        moderation_type: selectedType,
        engine: selectedEngine,
      };
      const isImage = selectedType.includes('image') || selectedType === 'video';
      if (isImage) {
        if (uploadedFile) {
          data.image_file = uploadedFile;
        } else {
          data.image_url = testInput;
        }
      } else {
        data.content = testInput;
      }
      const res = await api.testAIModeration(data);
      const duration = Date.now() - startTime;
      const entry = { ...res, timestamp: new Date().toISOString(), duration };
      setTestResponse(entry);
      setTestHistory(prev => [entry, ...prev].slice(0, 10));
    } catch (e: any) {
      const entry = { 
        error: e.message, 
        engine: selectedEngine, 
        moderation_type: selectedType, 
        input: testInput,
        timestamp: new Date().toISOString(),
        duration: Date.now() - startTime
      };
      setTestResponse(entry);
      setTestHistory(prev => [entry, ...prev].slice(0, 10));
    } finally {
      setTesting(false);
    }
  };

  const typeLabel = MODERATION_TYPES.find(t => t.key === selectedType)?.label || selectedType;
  const engineLabel = ENGINES.find(e => e.id === selectedEngine)?.label || selectedEngine;

  const getEngineStatus = (id: string) => {
    const engine = engines.find(e => e.id === id);
    if (!engine) return { color: 'text-gray-400', dot: 'bg-gray-300', label: 'Unknown' };
    if (engine.status === 'ready') return { color: 'text-green-600', dot: 'bg-green-500', label: 'Online' };
    if (engine.status === 'down') return { color: 'text-red-600', dot: 'bg-red-500', label: 'Down' };
    return { color: 'text-gray-400', dot: 'bg-gray-300', label: 'Not Configured' };
  };

  return (
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
          <Brain className="w-6 h-6" /> AI Moderation
        </h1>
        <p className="text-sm text-gray-500 mt-1">Configure AI moderation engines</p>
      </div>

      {/* Engine Status - Compact */}
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

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Left: Configuration */}
        <div className="space-y-4">
          {/* Type Selector */}
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

          {/* Engine Selector */}
          <div className="card p-4">
            <label className="text-sm font-semibold text-gray-700 block mb-2">Engine</label>
            <select
              value={selectedEngine}
              onChange={(e) => setSelectedEngine(e.target.value)}
              className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
            >
              {ENGINES.map(e => (
                <option key={e.id} value={e.id}>{e.label}</option>
              ))}
            </select>
          </div>

          {/* AI Moderation Instructions */}
          <div className="card p-4">
            <label className="text-sm font-semibold text-gray-700 block mb-2">
              Moderation Instructions
            </label>
            <p className="text-xs text-gray-500 mb-2">
              Provide specific guidelines for the AI to follow when moderating {typeLabel.toLowerCase()} content.
            </p>
            <textarea
              rows={4}
              value={systemPrompt}
              onChange={(e) => setSystemPrompt(e.target.value)}
              placeholder="Example: Flag content that promotes violence, hate speech, or illegal activities. Allow political discussion and criticism. Be lenient with humor and satire..."
              className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
            />
          </div>

          {/* Engine Configuration */}
          <div className="card p-4">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-gray-700">{engineLabel} Configuration</h3>
              <div className="text-xs text-gray-500">
                Current: {modelName || 'Not configured'}
              </div>
            </div>
            
            {selectedEngine === 'local_ai' && (
              <div>
                <label className="text-xs font-medium text-gray-600 block mb-1">Model</label>
                <select 
                  value={modelId}
                  onChange={(e) => {
                    const selected = LOCAL_MODELS.find(m => m.id === e.target.value);
                    setModelId(e.target.value);
                    setModelName(selected?.name || '');
                  }}
                  className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
                >
                  <option value="">Select model...</option>
                  {LOCAL_MODELS.map(m => (
                    <option key={m.id} value={m.id}>{m.name}</option>
                  ))}
                </select>
              </div>
            )}

            {selectedEngine === 'openrouter' && (
              <div className="space-y-3">
                <div>
                  <label className="text-xs font-medium text-gray-600 block mb-1">Model</label>
                  <div
                    onClick={() => setShowPicker(!showPicker)}
                    className="flex items-center justify-between px-3 py-2 border border-gray-300 rounded-lg cursor-pointer hover:bg-gray-50"
                  >
                    {modelId ? (
                      <span className="text-sm">{modelName || modelId}</span>
                    ) : (
                      <span className="text-sm text-gray-400">Select model...</span>
                    )}
                    <ChevronDown className={`w-4 h-4 text-gray-400 transition-transform ${showPicker ? 'rotate-180' : ''}`} />
                  </div>
                  
                  {showPicker && (
                    <div className="mt-2 border border-gray-200 rounded-lg overflow-hidden">
                      <div className="p-2 bg-gray-50">
                        <input
                          type="text"
                          placeholder="Search models..."
                          value={searchTerm}
                          onChange={(e) => {
                            setSearchTerm(e.target.value);
                            loadModels(e.target.value);
                          }}
                          className="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg"
                        />
                      </div>
                      <div className="max-h-64 overflow-y-auto">
                        {modelsLoading ? (
                          <div className="p-4 text-center text-sm text-gray-400">Loading...</div>
                        ) : (
                          models.map(m => (
                            <div
                              key={m.id}
                              onClick={() => {
                                setModelId(m.id);
                                setModelName(m.name);
                                setShowPicker(false);
                              }}
                              className="px-3 py-2 hover:bg-gray-50 cursor-pointer border-b border-gray-100"
                            >
                              <div className="text-sm font-medium">{m.name}</div>
                              <div className="text-xs text-gray-400">{m.id}</div>
                            </div>
                          ))
                        )}
                      </div>
                    </div>
                  )}
                </div>
              </div>
            )}

            {selectedEngine === 'openai' && (
              <p className="text-xs text-gray-500">OpenAI moderation is automatically configured. No additional settings needed.</p>
            )}

            {selectedEngine === 'google' && (
              <p className="text-xs text-gray-500">Google Vision SafeSearch is configured via service account. No additional settings needed.</p>
            )}

            {selectedEngine === 'azure' && (
              <div>
                <label className="text-xs font-medium text-gray-600 block mb-1">Deployment Name</label>
                <input
                  type="text"
                  value={modelId}
                  onChange={(e) => {
                    setModelId(e.target.value);
                    setModelName(e.target.value);
                  }}
                  placeholder="e.g., gpt-4o-vision"
                  className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
                />
                <p className="text-xs text-gray-500 mt-2">
                  Azure OpenAI deployment name (configured in Azure portal). Uses your Azure credits.
                </p>
              </div>
            )}
          </div>

          {/* Save Button */}
          <div className="card p-4 flex items-center justify-between">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={enabled}
                onChange={(e) => setEnabled(e.target.checked)}
                className="w-4 h-4 text-brand-600 rounded focus:ring-2 focus:ring-brand-500"
              />
              <span className="text-sm font-medium text-gray-700">Enable {typeLabel}</span>
            </label>
            <button
              onClick={handleSave}
              disabled={saving}
              className="btn-primary text-sm disabled:opacity-40"
            >
              {saving ? 'Saving...' : 'Save Configuration'}
            </button>
          </div>
        </div>

        {/* Right: Test Terminal */}
        <div className="space-y-4">
          {/* Test Input */}
          <div className="card p-4">
            <h3 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
              <Play className="w-4 h-4" /> Test Moderation
            </h3>
            
            {(selectedType.includes('image') || selectedType === 'video') ? (
              <div className="space-y-3">
                {/* File Upload */}
                <div className="flex gap-2">
                  <label className="flex-1">
                    <input
                      type="file"
                      accept="image/*"
                      onChange={(e) => {
                        const file = e.target.files?.[0];
                        if (file) {
                          handleFileUpload(file);
                        }
                      }}
                      className="hidden"
                    />
                    <div className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500 cursor-pointer hover:bg-gray-50 flex items-center justify-center gap-2">
                      <Upload className="w-4 h-4" />
                      {uploading ? 'Uploading...' : (uploadedFile ? `Uploaded: ${uploadedFile.name}` : 'Click to upload image...')}
                    </div>
                  </label>
                </div>
                
                {/* URL Input */}
                <div className="flex items-center gap-2 text-xs text-gray-500">
                  <span>OR</span>
                </div>
                
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={testInput}
                    onChange={(e) => setTestInput(e.target.value)}
                    placeholder="Image URL..."
                    className="flex-1 text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
                    onKeyDown={(e) => e.key === 'Enter' && handleTest()}
                  />
                </div>
              </div>
            ) : (
              <div className="flex gap-2">
                <input
                  type="text"
                  value={testInput}
                  onChange={(e) => setTestInput(e.target.value)}
                  placeholder="Test text..."
                  className="flex-1 text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500"
                  onKeyDown={(e) => e.key === 'Enter' && handleTest()}
                />
              </div>
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
                  onClick={() => {
                    setUploadedFile(null);
                    setTestInput('');
                  }}
                  className="text-sm text-gray-500 hover:text-gray-700"
                >
                  Clear Upload
                </button>
              )}
            </div>
          </div>

          {/* Terminal Output */}
          <div className="card p-0 overflow-hidden">
            <div className="bg-gray-900 px-4 py-2 flex items-center gap-2 border-b border-gray-700">
              <Terminal className="w-4 h-4 text-green-400" />
              <span className="text-xs font-mono text-green-400">moderation-test</span>
            </div>
            <div className="bg-gray-950 p-4 font-mono text-xs text-green-400 h-[500px] overflow-y-auto">
              {testHistory.length === 0 ? (
                <div className="text-gray-600">Waiting for test input...</div>
              ) : (
                <div className="space-y-4">
                  {testHistory.map((entry, idx) => (
                    <div key={idx} className="border-b border-gray-800 pb-3 last:border-0">
                      <div className="text-gray-500 mb-1">
                        [{new Date(entry.timestamp).toLocaleTimeString()}] {entry.engine} • {entry.moderation_type} • {entry.duration}ms
                      </div>
                      
                      {entry.error ? (
                        <div className="text-red-400">ERROR: {entry.error}</div>
                      ) : entry.result ? (
                        <div className="space-y-1">
                          <div className={entry.result.flagged ? 'text-red-400' : 'text-green-400'}>
                            {entry.result.flagged ? '⛔ FLAGGED' : '✅ CLEAN'}
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
  );
}
