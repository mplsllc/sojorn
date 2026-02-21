// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useEffect, useState } from 'react';
import { HardDrive, Folder, FileImage, Film, Trash2, ExternalLink, ChevronRight, ArrowLeft, RefreshCw, Image, Copy, Check } from 'lucide-react';

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function isImageKey(key: string): boolean {
  return /\.(jpg|jpeg|png|gif|webp|svg|avif|bmp)$/i.test(key);
}

function isVideoKey(key: string): boolean {
  return /\.(mp4|webm|mov|avi|mkv)$/i.test(key);
}

export default function StoragePage() {
  const [stats, setStats] = useState<any>(null);
  const [objects, setObjects] = useState<any[]>([]);
  const [folders, setFolders] = useState<string[]>([]);
  const [selectedBucket, setSelectedBucket] = useState('');
  const [prefix, setPrefix] = useState('');
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [browsing, setBrowsing] = useState(false);
  const [selectedObject, setSelectedObject] = useState<any>(null);
  const [deleting, setDeleting] = useState('');
  const [copiedUrl, setCopiedUrl] = useState('');
  const [statsLoading, setStatsLoading] = useState(true);

  useEffect(() => {
    loadStats();
  }, []);

  const loadStats = async () => {
    setStatsLoading(true);
    try {
      const data = await api.getStorageStats();
      setStats(data);
      if (data.buckets?.length > 0 && !selectedBucket) {
        setSelectedBucket(data.buckets[0].name);
      }
    } catch {}
    setStatsLoading(false);
    setLoading(false);
  };

  const browse = async (bucket?: string, pfx?: string, cursor?: string) => {
    setBrowsing(true);
    const b = bucket || selectedBucket;
    const p = pfx ?? prefix;
    try {
      const data = await api.listStorageObjects({ bucket: b, prefix: p || undefined, cursor: cursor || undefined, limit: 50 });
      if (cursor) {
        setObjects((prev) => [...prev, ...data.objects]);
      } else {
        setObjects(data.objects);
      }
      setFolders(data.folders || []);
      setNextCursor(data.next_cursor || null);
      setSelectedBucket(b);
      setPrefix(p);
    } catch {}
    setBrowsing(false);
  };

  const navigateToFolder = (folder: string) => {
    setObjects([]);
    setFolders([]);
    browse(selectedBucket, folder);
  };

  const navigateUp = () => {
    if (!prefix) return;
    const parts = prefix.replace(/\/$/, '').split('/');
    parts.pop();
    const newPrefix = parts.length > 0 ? parts.join('/') + '/' : '';
    setObjects([]);
    setFolders([]);
    browse(selectedBucket, newPrefix);
  };

  const handleDelete = async (bucket: string, key: string) => {
    if (!confirm(`Delete ${key}? This cannot be undone.`)) return;
    setDeleting(key);
    try {
      await api.deleteStorageObject(bucket, key);
      setObjects((prev) => prev.filter((o) => o.key !== key));
      if (selectedObject?.key === key) setSelectedObject(null);
    } catch {}
    setDeleting('');
  };

  const copyUrl = (url: string) => {
    navigator.clipboard.writeText(url);
    setCopiedUrl(url);
    setTimeout(() => setCopiedUrl(''), 2000);
  };

  const switchBucket = (bucket: string) => {
    setSelectedBucket(bucket);
    setPrefix('');
    setObjects([]);
    setFolders([]);
    setSelectedObject(null);
    browse(bucket, '');
  };

  return (
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">R2 Storage</h1>
          <p className="text-sm text-gray-500 mt-1">Browse and manage Cloudflare R2 media buckets</p>
        </div>
        <button onClick={loadStats} className="btn-secondary text-sm flex items-center gap-2" disabled={statsLoading}>
          <RefreshCw className={`w-4 h-4 ${statsLoading ? 'animate-spin' : ''}`} /> Refresh Stats
        </button>
      </div>

      {/* Bucket Stats */}
      {loading ? (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="card p-5 animate-pulse">
              <div className="h-4 bg-warm-300 rounded w-24 mb-3" />
              <div className="h-8 bg-warm-300 rounded w-16" />
            </div>
          ))}
        </div>
      ) : stats ? (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {stats.buckets?.map((b: any) => (
            <button
              key={b.name}
              onClick={() => switchBucket(b.name)}
              className={`card p-5 text-left transition-all ${selectedBucket === b.name ? 'ring-2 ring-brand-500' : 'hover:shadow-md'}`}
            >
              <div className="flex items-center gap-3 mb-3">
                <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${b.name.includes('video') ? 'bg-purple-100 text-purple-600' : 'bg-blue-100 text-blue-600'}`}>
                  {b.name.includes('video') ? <Film className="w-5 h-5" /> : <FileImage className="w-5 h-5" />}
                </div>
                <div>
                  <p className="font-semibold text-gray-900 text-sm">{b.name}</p>
                  <p className="text-xs text-gray-400">{b.domain}</p>
                </div>
              </div>
              <div className="flex items-center justify-between text-sm">
                <span className="text-gray-500">{b.object_count.toLocaleString()} objects</span>
                <span className="font-medium text-gray-700">{formatBytes(b.total_size)}</span>
              </div>
            </button>
          ))}
          <div className="card p-5">
            <div className="flex items-center gap-3 mb-3">
              <div className="w-10 h-10 rounded-lg flex items-center justify-center bg-green-100 text-green-600">
                <HardDrive className="w-5 h-5" />
              </div>
              <div>
                <p className="font-semibold text-gray-900 text-sm">Total Storage</p>
                <p className="text-xs text-gray-400">All buckets combined</p>
              </div>
            </div>
            <div className="flex items-center justify-between text-sm">
              <span className="text-gray-500">{stats.total_objects?.toLocaleString()} objects</span>
              <span className="font-medium text-gray-700">{formatBytes(stats.total_size || 0)}</span>
            </div>
          </div>
        </div>
      ) : null}

      {/* Browser Controls */}
      {selectedBucket && (
        <div className="card p-4 mb-4">
          <div className="flex items-center gap-3">
            {prefix && (
              <button onClick={navigateUp} className="btn-secondary text-sm flex items-center gap-1">
                <ArrowLeft className="w-4 h-4" /> Up
              </button>
            )}
            <div className="flex items-center gap-1 text-sm text-gray-500 flex-1 min-w-0">
              <HardDrive className="w-4 h-4 flex-shrink-0" />
              <span className="font-medium text-gray-700">{selectedBucket}</span>
              {prefix && (
                <>
                  <ChevronRight className="w-3 h-3" />
                  <span className="truncate">{prefix}</span>
                </>
              )}
            </div>
            <button
              onClick={() => browse()}
              className="btn-primary text-sm flex items-center gap-2"
              disabled={browsing}
            >
              {browsing ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Folder className="w-4 h-4" />}
              {objects.length > 0 ? 'Refresh' : 'Browse'}
            </button>
          </div>
        </div>
      )}

      {/* Object List */}
      {(folders.length > 0 || objects.length > 0) && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <div className="lg:col-span-2">
            <div className="card overflow-hidden">
              {/* Folders */}
              {folders.map((folder) => (
                <button
                  key={folder}
                  onClick={() => navigateToFolder(folder)}
                  className="flex items-center gap-3 px-4 py-3 w-full text-left hover:bg-warm-100 border-b border-warm-200 transition-colors"
                >
                  <Folder className="w-5 h-5 text-yellow-500 flex-shrink-0" />
                  <span className="text-sm font-medium text-gray-700 truncate">{folder}</span>
                  <ChevronRight className="w-4 h-4 text-gray-400 ml-auto flex-shrink-0" />
                </button>
              ))}

              {/* Files */}
              {objects.map((obj) => (
                <div
                  key={obj.key}
                  className={`flex items-center gap-3 px-4 py-3 border-b border-warm-200 hover:bg-warm-100 cursor-pointer transition-colors ${selectedObject?.key === obj.key ? 'bg-brand-50' : ''}`}
                  onClick={() => setSelectedObject(obj)}
                >
                  {isImageKey(obj.key) ? (
                    <Image className="w-5 h-5 text-blue-500 flex-shrink-0" />
                  ) : isVideoKey(obj.key) ? (
                    <Film className="w-5 h-5 text-purple-500 flex-shrink-0" />
                  ) : (
                    <FileImage className="w-5 h-5 text-gray-400 flex-shrink-0" />
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-700 truncate">
                      {obj.key.split('/').pop() || obj.key}
                    </p>
                    <p className="text-xs text-gray-400">
                      {formatBytes(obj.size)} &middot; {new Date(obj.last_modified).toLocaleDateString()}
                    </p>
                  </div>
                  <div className="flex items-center gap-1 flex-shrink-0">
                    <button
                      onClick={(e) => { e.stopPropagation(); copyUrl(obj.url); }}
                      className="p-1.5 rounded hover:bg-warm-200 text-gray-400 hover:text-gray-600"
                      title="Copy URL"
                    >
                      {copiedUrl === obj.url ? <Check className="w-4 h-4 text-green-500" /> : <Copy className="w-4 h-4" />}
                    </button>
                    <a
                      href={obj.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      onClick={(e) => e.stopPropagation()}
                      className="p-1.5 rounded hover:bg-warm-200 text-gray-400 hover:text-gray-600"
                      title="Open in new tab"
                    >
                      <ExternalLink className="w-4 h-4" />
                    </a>
                    <button
                      onClick={(e) => { e.stopPropagation(); handleDelete(selectedBucket, obj.key); }}
                      className="p-1.5 rounded hover:bg-red-50 text-gray-400 hover:text-red-600"
                      title="Delete"
                      disabled={deleting === obj.key}
                    >
                      <Trash2 className={`w-4 h-4 ${deleting === obj.key ? 'animate-pulse' : ''}`} />
                    </button>
                  </div>
                </div>
              ))}

              {objects.length === 0 && folders.length === 0 && !browsing && (
                <div className="p-8 text-center text-gray-400 text-sm">No objects found in this location.</div>
              )}

              {browsing && (
                <div className="p-4 text-center text-gray-400 text-sm">
                  <RefreshCw className="w-5 h-5 animate-spin inline-block mr-2" />Loading...
                </div>
              )}
            </div>

            {/* Load More */}
            {nextCursor && (
              <button
                onClick={() => browse(selectedBucket, prefix, nextCursor)}
                className="mt-3 btn-secondary text-sm w-full"
                disabled={browsing}
              >
                Load More
              </button>
            )}
          </div>

          {/* Detail / Preview Panel */}
          <div className="lg:col-span-1">
            {selectedObject ? (
              <div className="card p-4 sticky top-6">
                {/* Preview */}
                {isImageKey(selectedObject.key) && (
                  <div className="mb-4 rounded-lg overflow-hidden bg-warm-200 aspect-square flex items-center justify-center">
                    <img
                      src={selectedObject.url}
                      alt={selectedObject.key}
                      className="max-w-full max-h-full object-contain"
                      onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }}
                    />
                  </div>
                )}
                {isVideoKey(selectedObject.key) && (
                  <div className="mb-4 rounded-lg overflow-hidden bg-black aspect-video">
                    <video src={selectedObject.url} controls className="w-full h-full" />
                  </div>
                )}

                <h3 className="text-sm font-semibold text-gray-900 break-all mb-3">
                  {selectedObject.key.split('/').pop() || selectedObject.key}
                </h3>

                <div className="space-y-2 text-sm">
                  <div className="flex justify-between">
                    <span className="text-gray-500">Key</span>
                    <span className="text-gray-700 text-right break-all ml-4 max-w-[60%]">{selectedObject.key}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Size</span>
                    <span className="text-gray-700">{formatBytes(selectedObject.size)}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">Modified</span>
                    <span className="text-gray-700">{new Date(selectedObject.last_modified).toLocaleString()}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-gray-500">ETag</span>
                    <span className="text-gray-700 font-mono text-xs">{selectedObject.etag?.slice(0, 12)}...</span>
                  </div>
                </div>

                <div className="mt-4 space-y-2">
                  <button
                    onClick={() => copyUrl(selectedObject.url)}
                    className="btn-secondary text-sm w-full flex items-center justify-center gap-2"
                  >
                    {copiedUrl === selectedObject.url ? <Check className="w-4 h-4 text-green-500" /> : <Copy className="w-4 h-4" />}
                    {copiedUrl === selectedObject.url ? 'Copied!' : 'Copy URL'}
                  </button>
                  <a
                    href={selectedObject.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn-secondary text-sm w-full flex items-center justify-center gap-2"
                  >
                    <ExternalLink className="w-4 h-4" /> Open in Browser
                  </a>
                  <button
                    onClick={() => handleDelete(selectedBucket, selectedObject.key)}
                    className="w-full py-2 px-4 rounded-lg text-sm font-medium text-red-600 border border-red-200 hover:bg-red-50 transition-colors flex items-center justify-center gap-2"
                    disabled={deleting === selectedObject.key}
                  >
                    <Trash2 className="w-4 h-4" /> Delete Object
                  </button>
                </div>
              </div>
            ) : (
              <div className="card p-8 text-center text-gray-400 text-sm">
                <FileImage className="w-8 h-8 mx-auto mb-2 opacity-50" />
                Select an object to view details
              </div>
            )}
          </div>
        </div>
      )}
    </AdminShell>
  );
}
