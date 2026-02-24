// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useEffect, useState, useCallback } from 'react';
import { Cpu, Play, Square, Trash2, Download, RefreshCw, HardDrive, Zap, AlertTriangle } from 'lucide-react';

interface OllamaModel {
  name: string;
  parameter_size: string;
  quantization_level: string;
  family: string;
  size_bytes: number;
  size_mb: number;
  running: boolean;
  vram_bytes: number;
  context_length: number;
  expires_at?: string;
  modified_at: string;
}

function formatSize(mb: number): string {
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)} GB`;
  return `${mb} MB`;
}

function ModelCard({ model, onLoad, onUnload, onDelete, busy }: {
  model: OllamaModel;
  onLoad: () => void;
  onUnload: () => void;
  onDelete: () => void;
  busy: string | null;
}) {
  const isBusy = busy === model.name;
  const roleLabel = model.name.includes('guard') ? 'Moderation'
    : model.name.includes('dolphin') || model.name.includes('qwen') ? 'Creative / General'
    : model.name.includes('devstral') ? 'Code'
    : 'General';

  const roleColor = model.name.includes('guard') ? 'bg-red-100 text-red-700'
    : model.name.includes('devstral') ? 'bg-gray-100 text-gray-600'
    : 'bg-blue-100 text-blue-700';

  return (
    <div className={`card p-5 border-l-4 ${model.running ? 'border-green-500' : 'border-gray-300'}`}>
      <div className="flex items-start justify-between">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <h3 className="text-base font-semibold text-gray-900 truncate">{model.name}</h3>
            <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${roleColor}`}>{roleLabel}</span>
          </div>
          <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-500 mt-2">
            <span className="flex items-center gap-1">
              <Cpu className="w-3.5 h-3.5" /> {model.parameter_size}
            </span>
            <span className="flex items-center gap-1">
              <HardDrive className="w-3.5 h-3.5" /> {formatSize(model.size_mb)}
            </span>
            <span>{model.quantization_level}</span>
            <span className="text-gray-400">{model.family}</span>
          </div>
          {model.running && (
            <div className="flex items-center gap-3 mt-2 text-xs">
              <span className="flex items-center gap-1 text-green-600 font-medium">
                <Zap className="w-3.5 h-3.5" /> Running
              </span>
              {model.context_length > 0 && (
                <span className="text-gray-400">ctx: {model.context_length.toLocaleString()}</span>
              )}
              {model.expires_at && (
                <span className="text-gray-400">
                  expires: {new Date(model.expires_at).toLocaleTimeString()}
                </span>
              )}
            </div>
          )}
        </div>
        <div className="flex items-center gap-1 ml-3 flex-shrink-0">
          {model.running ? (
            <button
              type="button"
              onClick={onUnload}
              disabled={isBusy}
              className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium bg-orange-50 text-orange-700 hover:bg-orange-100 disabled:opacity-50"
              title="Unload from memory"
            >
              <Square className="w-3.5 h-3.5" /> {isBusy ? 'Stopping...' : 'Stop'}
            </button>
          ) : (
            <button
              type="button"
              onClick={onLoad}
              disabled={isBusy}
              className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium bg-green-50 text-green-700 hover:bg-green-100 disabled:opacity-50"
              title="Load into memory"
            >
              <Play className="w-3.5 h-3.5" /> {isBusy ? 'Starting...' : 'Start'}
            </button>
          )}
          <button
            type="button"
            onClick={onDelete}
            disabled={isBusy || model.running}
            className="p-1.5 rounded-lg text-red-400 hover:text-red-600 hover:bg-red-50 disabled:opacity-30"
            title={model.running ? 'Stop model before deleting' : 'Delete model'}
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );
}

export default function AIModelsPage() {
  const [models, setModels] = useState<OllamaModel[]>([]);
  const [loading, setLoading] = useState(true);
  const [ollamaRunning, setOllamaRunning] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [pullName, setPullName] = useState('');
  const [pulling, setPulling] = useState(false);
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  const showMsg = (type: 'success' | 'error', text: string) => {
    setMessage({ type, text });
    setTimeout(() => setMessage(null), 4000);
  };

  const fetchModels = useCallback(() => {
    setLoading(true);
    api.getOllamaStatus()
      .then((data) => {
        setModels(data.models ?? []);
        setOllamaRunning(data.ollama_running ?? false);
      })
      .catch(() => { setOllamaRunning(false); })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => { fetchModels(); }, [fetchModels]);

  const handleLoad = async (name: string) => {
    setBusy(name);
    try {
      await api.ollamaLoadModel(name);
      showMsg('success', `${name} loaded into memory`);
      fetchModels();
    } catch (e: any) {
      showMsg('error', e.message || 'Failed to load model');
    }
    setBusy(null);
  };

  const handleUnload = async (name: string) => {
    setBusy(name);
    try {
      await api.ollamaUnloadModel(name);
      showMsg('success', `${name} unloaded from memory`);
      fetchModels();
    } catch (e: any) {
      showMsg('error', e.message || 'Failed to unload model');
    }
    setBusy(null);
  };

  const handleDelete = async (name: string) => {
    if (!confirm(`Permanently delete model "${name}"? This removes the model files from disk.`)) return;
    setBusy(name);
    try {
      await api.ollamaDeleteModel(name);
      showMsg('success', `${name} deleted`);
      fetchModels();
    } catch (e: any) {
      showMsg('error', e.message || 'Failed to delete model');
    }
    setBusy(null);
  };

  const handlePull = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pullName.trim()) return;
    setPulling(true);
    try {
      await api.ollamaPullModel(pullName.trim());
      showMsg('success', `${pullName.trim()} pulled successfully`);
      setPullName('');
      fetchModels();
    } catch (err: any) {
      showMsg('error', err.message || 'Failed to pull model');
    }
    setPulling(false);
  };

  const runningCount = models.filter((m) => m.running).length;
  const totalSizeMB = models.reduce((acc, m) => acc + m.size_mb, 0);

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">AI Models</h1>
          <p className="text-sm text-gray-500 mt-1">Manage Ollama models — start, stop, pull, and delete</p>
        </div>
        <button type="button" onClick={fetchModels} className="btn-secondary text-sm flex items-center gap-1">
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} /> Refresh
        </button>
      </div>

      {/* Toast */}
      {message && (
        <div className={`mb-4 px-4 py-3 rounded-lg text-sm font-medium ${
          message.type === 'success' ? 'bg-green-50 text-green-700 border border-green-200' : 'bg-red-50 text-red-700 border border-red-200'
        }`}>
          {message.text}
        </div>
      )}

      {/* Ollama Status Banner */}
      {!ollamaRunning && !loading && (
        <div className="mb-4 px-4 py-3 rounded-lg bg-red-50 border border-red-200 flex items-center gap-2 text-sm text-red-700">
          <AlertTriangle className="w-5 h-5 flex-shrink-0" />
          <span><strong>Ollama is not reachable.</strong> The Ollama service may be down on the server. Models cannot be managed until it is running.</span>
        </div>
      )}

      {/* Summary Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div className="card p-4 text-center">
          <p className="text-2xl font-bold text-gray-900">{models.length}</p>
          <p className="text-xs text-gray-500">Installed Models</p>
        </div>
        <div className="card p-4 text-center">
          <p className="text-2xl font-bold text-green-600">{runningCount}</p>
          <p className="text-xs text-gray-500">Currently Running</p>
        </div>
        <div className="card p-4 text-center">
          <p className="text-2xl font-bold text-gray-900">{formatSize(totalSizeMB)}</p>
          <p className="text-xs text-gray-500">Total Disk Usage</p>
        </div>
      </div>

      {/* Pull New Model */}
      <div className="card p-5 mb-6">
        <div className="flex items-center gap-2 mb-3">
          <Download className="w-5 h-5 text-brand-500" />
          <h3 className="text-base font-semibold text-gray-900">Pull New Model</h3>
        </div>
        <form onSubmit={handlePull} className="flex gap-2">
          <input
            className="input flex-1 max-w-md"
            placeholder="e.g. llama3.2:1b, phi3:mini, gemma2:2b"
            value={pullName}
            onChange={(e) => setPullName(e.target.value)}
            disabled={pulling}
          />
          <button type="submit" className="btn-primary text-sm flex items-center gap-1" disabled={pulling || !pullName.trim()}>
            <Download className="w-4 h-4" /> {pulling ? 'Pulling...' : 'Pull'}
          </button>
        </form>
        <p className="text-xs text-gray-400 mt-2">
          Download a model from the Ollama registry. This may take a while for large models.
        </p>
      </div>

      {/* Model List */}
      {loading ? (
        <div className="space-y-3">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="card p-5 animate-pulse">
              <div className="h-5 bg-warm-300 rounded w-48 mb-2" />
              <div className="h-4 bg-warm-300 rounded w-32" />
            </div>
          ))}
        </div>
      ) : models.length === 0 ? (
        <div className="card p-12 text-center">
          <Cpu className="w-12 h-12 text-gray-300 mx-auto mb-3" />
          <p className="text-gray-500">No models installed</p>
          <p className="text-xs text-gray-400 mt-1">Use the pull form above to download a model</p>
        </div>
      ) : (
        <div className="space-y-3">
          {models
            .sort((a, b) => (a.running === b.running ? 0 : a.running ? -1 : 1))
            .map((model) => (
              <ModelCard
                key={model.name}
                model={model}
                onLoad={() => handleLoad(model.name)}
                onUnload={() => handleUnload(model.name)}
                onDelete={() => handleDelete(model.name)}
                busy={busy}
              />
            ))}
        </div>
      )}
    </AdminShell>
  );
}
