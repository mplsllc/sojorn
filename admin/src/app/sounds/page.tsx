// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { formatDate } from '@/lib/utils';
import { useEffect, useRef, useState } from 'react';
import { RefreshCw, Upload, Music2, ToggleLeft, ToggleRight, Pencil, Check, X } from 'lucide-react';

type Sound = {
  id: string;
  title: string;
  bucket: string;
  duration_ms: number | null;
  use_count: number;
  is_active: boolean;
  audio_url: string;
  created_at: string;
};

type BucketFilter = 'all' | 'library' | 'user';

export default function SoundsPage() {
  const [sounds, setSounds] = useState<Sound[]>([]);
  const [loading, setLoading] = useState(true);
  const [bucket, setBucket] = useState<BucketFilter>('all');
  const [uploading, setUploading] = useState(false);
  const [uploadTitle, setUploadTitle] = useState('');
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const [togglingId, setTogglingId] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  const fetchSounds = (b: BucketFilter = bucket) => {
    setLoading(true);
    api.listAdminSounds(b === 'all' ? undefined : b)
      .then((data) => setSounds(data.sounds ?? []))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchSounds(bucket); }, [bucket]);

  const handleUpload = async () => {
    if (!uploadFile || !uploadTitle.trim()) return;
    setUploading(true);
    try {
      const { url, key } = await api.uploadMedia(uploadFile, 'audio');
      const r2Key = key ?? (url.includes('.net/') ? url.split('.net/')[1] : url);
      await api.createLibrarySound({ title: uploadTitle.trim(), r2_key: r2Key, bucket: 'library' });
      setUploadTitle('');
      setUploadFile(null);
      if (fileRef.current) fileRef.current.value = '';
      fetchSounds(bucket);
    } catch (e: any) {
      alert(`Upload failed: ${e.message}`);
    } finally {
      setUploading(false);
    }
  };

  const toggleActive = async (sound: Sound) => {
    setTogglingId(sound.id);
    try {
      await api.updateSound(sound.id, { is_active: !sound.is_active });
      setSounds((prev) => prev.map((s) => s.id === sound.id ? { ...s, is_active: !s.is_active } : s));
    } catch (e: any) {
      alert(`Update failed: ${e.message}`);
    } finally {
      setTogglingId(null);
    }
  };

  const startEdit = (sound: Sound) => {
    setEditingId(sound.id);
    setEditTitle(sound.title);
  };

  const saveEdit = async (sound: Sound) => {
    if (!editTitle.trim()) return;
    try {
      await api.updateSound(sound.id, { title: editTitle.trim() });
      setSounds((prev) => prev.map((s) => s.id === sound.id ? { ...s, title: editTitle.trim() } : s));
      setEditingId(null);
    } catch (e: any) {
      alert(`Update failed: ${e.message}`);
    }
  };

  const fmtDuration = (ms: number | null) => {
    if (!ms) return '—';
    const s = Math.round(ms / 1000);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  };

  const tabs: { key: BucketFilter; label: string }[] = [
    { key: 'all', label: 'All' },
    { key: 'library', label: 'Library' },
    { key: 'user', label: 'User Sounds' },
  ];

  return (
    <AdminOnlyGuard>
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Soundbank</h1>
          <p className="text-sm text-gray-500 mt-1">
            Curated library tracks and user-generated audio. Trending sorted by play count.
          </p>
        </div>
        <button
          onClick={() => fetchSounds(bucket)}
          className="flex items-center gap-1.5 px-3 py-2 border rounded-lg text-sm hover:bg-gray-50"
        >
          <RefreshCw className="w-4 h-4" /> Reload
        </button>
      </div>

      {/* Upload library track */}
      <div className="bg-white border rounded-xl p-5 mb-6">
        <h2 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
          <Upload className="w-4 h-4" /> Upload Library Track
        </h2>
        <div className="flex gap-3 flex-wrap">
          <input
            type="text"
            placeholder="Track title"
            value={uploadTitle}
            onChange={(e) => setUploadTitle(e.target.value)}
            className="flex-1 min-w-48 border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-400"
          />
          <input
            ref={fileRef}
            type="file"
            accept="audio/*"
            onChange={(e) => setUploadFile(e.target.files?.[0] ?? null)}
            className="text-sm text-gray-600 file:mr-3 file:py-1.5 file:px-3 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-brand-50 file:text-brand-700 hover:file:bg-brand-100"
          />
          <button
            onClick={handleUpload}
            disabled={uploading || !uploadFile || !uploadTitle.trim()}
            className="px-4 py-2 bg-brand-600 text-white rounded-lg text-sm font-medium hover:bg-brand-700 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1.5"
          >
            {uploading ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Music2 className="w-4 h-4" />}
            {uploading ? 'Uploading…' : 'Add Track'}
          </button>
        </div>
      </div>

      {/* Bucket filter tabs */}
      <div className="flex gap-1 mb-4 border-b border-gray-200">
        {tabs.map((t) => (
          <button
            key={t.key}
            onClick={() => setBucket(t.key)}
            className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
              bucket === t.key
                ? 'border-brand-500 text-brand-600'
                : 'border-transparent text-gray-500 hover:text-gray-700'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* Sounds table */}
      <div className="bg-white rounded-xl border overflow-hidden">
        {loading ? (
          <div className="p-8 text-center text-gray-400">Loading…</div>
        ) : sounds.length === 0 ? (
          <div className="p-8 text-center text-gray-400">No sounds found.</div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Title</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Bucket</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Duration</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Plays</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Added</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Active</th>
                <th className="px-4 py-3 text-right font-medium text-gray-600">Preview</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {sounds.map((s) => (
                <tr key={s.id} className={`hover:bg-gray-50 ${!s.is_active ? 'opacity-50' : ''}`}>
                  <td className="px-4 py-3 max-w-xs">
                    {editingId === s.id ? (
                      <div className="flex items-center gap-1.5">
                        <input
                          autoFocus
                          value={editTitle}
                          onChange={(e) => setEditTitle(e.target.value)}
                          onKeyDown={(e) => { if (e.key === 'Enter') saveEdit(s); if (e.key === 'Escape') setEditingId(null); }}
                          className="flex-1 border rounded px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-brand-400"
                        />
                        <button onClick={() => saveEdit(s)} className="text-green-600 hover:text-green-700"><Check className="w-4 h-4" /></button>
                        <button onClick={() => setEditingId(null)} className="text-gray-400 hover:text-gray-600"><X className="w-4 h-4" /></button>
                      </div>
                    ) : (
                      <div className="flex items-center gap-1.5 group">
                        <span className="truncate text-gray-800">{s.title}</span>
                        <button
                          onClick={() => startEdit(s)}
                          className="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-gray-600 transition-opacity"
                        >
                          <Pencil className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${
                      s.bucket === 'library'
                        ? 'bg-purple-100 text-purple-700'
                        : 'bg-blue-100 text-blue-700'
                    }`}>
                      {s.bucket}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-gray-500">{fmtDuration(s.duration_ms)}</td>
                  <td className="px-4 py-3 text-gray-700">{s.use_count.toLocaleString()}</td>
                  <td className="px-4 py-3 text-gray-500">{formatDate(s.created_at)}</td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => toggleActive(s)}
                      disabled={togglingId === s.id}
                      className="text-gray-400 hover:text-brand-600 transition-colors disabled:opacity-50"
                      title={s.is_active ? 'Deactivate' : 'Activate'}
                    >
                      {s.is_active
                        ? <ToggleRight className="w-6 h-6 text-brand-500" />
                        : <ToggleLeft className="w-6 h-6" />
                      }
                    </button>
                  </td>
                  <td className="px-4 py-3 text-right">
                    <a
                      href={s.audio_url}
                      target="_blank"
                      rel="noreferrer"
                      className="text-xs text-brand-600 hover:underline"
                    >
                      Play ↗
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </AdminShell>
    </AdminOnlyGuard>
  );
}
