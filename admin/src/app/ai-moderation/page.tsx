// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useEffect, useState, useCallback, useRef } from 'react';
import { Brain, Play, Loader2, Eye, MessageSquare, Video, Shield, MapPin, Users, AlertTriangle, Cpu, Terminal, Upload } from 'lucide-react';

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

// Fetched dynamically from Ollama via /ai/models/local

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
  
  // Test states
  const [testInput, setTestInput] = useState('');
  const [testResponse, setTestResponse] = useState<any>(null);
  const [testing, setTesting] = useState(false);
  const [testHistory, setTestHistory] = useState<any[]>([]);
  const [uploadedFile, setUploadedFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [localModels, setLocalModels] = useState<{id: string; name: string}[]>([]);

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
      const result = await api.uploadTestImage(file);
      setTestInput(result.url);
      setUploadedFile(file);
    } catch (e: any) {
      console.error('Upload error:', e);
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
      const data: any = {
        moderation_type: selectedType,
        engine: selectedEngine,
      };
      if (isImage) {
        data.image_url = testInput; // Use the uploaded file URL
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
                    const selected = localModels.find(m => m.id === e.target.value);
                    setModelId(e.target.value);
                    setModelName(selected?.name || '');
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

            {selectedEngine === 'sightengine' && (
              <p className="text-xs text-gray-500">SightEngine is configured via API credentials in the server environment. Supports both text and image moderation.</p>
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
