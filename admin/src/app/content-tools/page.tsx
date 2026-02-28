// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { useCallback, useEffect, useRef, useState } from 'react';
import { UserPlus, Upload, AlertCircle, CheckCircle, Copy, FileText, Link2, Search, Globe, Download, Check, X, Loader2, ExternalLink, Play, Image as ImageIcon, Cookie, Trash2, TestTube, ChevronDown, ChevronRight, Shield } from 'lucide-react';

// ─── CSV Parser ───────────────────────────────────────
function parseCsvLine(line: string): string[] {
  const result: string[] = [];
  let inQuotes = false;
  let current = '';
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      inQuotes = !inQuotes;
    } else if (ch === ',' && !inQuotes) {
      result.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  result.push(current.trim());
  return result;
}

// ─── User Search Component ───────────────────────────
function UserSearch({ value, onChange }: { value: string; onChange: (id: string, display: string) => void }) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState('');
  const debounceRef = useRef<NodeJS.Timeout>();
  const wrapperRef = useRef<HTMLDivElement>(null);

  // Close dropdown on outside click
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const search = useCallback((q: string) => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    if (q.length < 2) { setResults([]); setOpen(false); return; }
    debounceRef.current = setTimeout(async () => {
      setLoading(true);
      try {
        const data = await api.listUsers({ search: q, limit: 8 });
        setResults(data.users || []);
        setOpen(true);
      } catch { setResults([]); }
      setLoading(false);
    }, 300);
  }, []);

  const handleSelect = (user: any) => {
    const display = `@${user.handle || '?'} — ${user.display_name || user.email || ''}`;
    setSelected(display);
    setQuery('');
    setOpen(false);
    onChange(user.id, display);
  };

  const handleClear = () => {
    setSelected('');
    setQuery('');
    onChange('', '');
  };

  return (
    <div ref={wrapperRef} className="relative">
      <label className="block text-sm font-medium text-gray-700 mb-1">Author *</label>
      {selected ? (
        <div className="flex items-center gap-2 px-3 py-2 border border-brand-300 bg-brand-50 rounded-lg text-sm">
          <span className="flex-1 truncate font-medium text-brand-700">{selected}</span>
          <button onClick={handleClear} className="text-gray-400 hover:text-gray-600"><X className="w-4 h-4" /></button>
        </div>
      ) : (
        <>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input
              type="text"
              value={query}
              onChange={(e) => { setQuery(e.target.value); search(e.target.value); }}
              onFocus={() => results.length > 0 && setOpen(true)}
              className="w-full pl-10 pr-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
              placeholder="Search by handle, name, or email..."
            />
            {loading && <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 animate-spin" />}
          </div>
          {open && results.length > 0 && (
            <div className="absolute z-50 mt-1 w-full bg-white border border-warm-300 rounded-lg shadow-lg max-h-60 overflow-y-auto">
              {results.map((u) => (
                <button
                  key={u.id}
                  onClick={() => handleSelect(u)}
                  className="w-full text-left px-3 py-2 hover:bg-brand-50 border-b border-warm-100 last:border-0 flex items-center gap-3"
                >
                  <div className="w-8 h-8 bg-brand-100 rounded-lg flex items-center justify-center text-brand-600 text-xs font-bold flex-shrink-0">
                    {(u.handle || u.email || '?')[0].toUpperCase()}
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-gray-900 truncate">{u.display_name || u.handle || '—'}</p>
                    <p className="text-xs text-gray-500 truncate">@{u.handle || '—'} · {u.email}</p>
                  </div>
                </button>
              ))}
            </div>
          )}
          {open && results.length === 0 && query.length >= 2 && !loading && (
            <div className="absolute z-50 mt-1 w-full bg-white border border-warm-300 rounded-lg shadow-lg p-3">
              <p className="text-sm text-gray-500">No users found</p>
            </div>
          )}
        </>
      )}
      {/* Still allow manual UUID entry */}
      {!selected && (
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value, '')}
          className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm font-mono mt-2 focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          placeholder="...or paste User ID directly"
        />
      )}
    </div>
  );
}

export default function ContentToolsPage() {
  const [activeTab, setActiveTab] = useState<'create-user' | 'import' | 'social'>('create-user');

  return (
    <AdminOnlyGuard>
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Content Tools</h1>
        <p className="text-gray-500 mt-1">Create users, import content, and pull from social platforms</p>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 mb-6 bg-warm-200 rounded-lg p-1 w-fit">
        <button
          onClick={() => setActiveTab('create-user')}
          className={`flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
            activeTab === 'create-user'
              ? 'bg-white text-gray-900 shadow-sm'
              : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          <UserPlus className="w-4 h-4" />
          Create User
        </button>
        <button
          onClick={() => setActiveTab('import')}
          className={`flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
            activeTab === 'import'
              ? 'bg-white text-gray-900 shadow-sm'
              : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          <Upload className="w-4 h-4" />
          Import Content
        </button>
        <button
          onClick={() => setActiveTab('social')}
          className={`flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
            activeTab === 'social'
              ? 'bg-white text-gray-900 shadow-sm'
              : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          <Globe className="w-4 h-4" />
          Social Import
        </button>
      </div>

      {activeTab === 'create-user' ? <CreateUserPanel /> : activeTab === 'import' ? <ImportContentPanel /> : <SocialImportPanel />}
    </AdminShell>
    </AdminOnlyGuard>
  );
}

// ─── Create User Panel ────────────────────────────────
function CreateUserPanel() {
  const [form, setForm] = useState({
    email: '',
    handle: '',
    display_name: '',
    bio: '',
    role: 'user',
    verified: false,
    official: false,
  });
  const passwordRef = useRef<HTMLInputElement>(null);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null);

  const update = (key: string, value: any) => setForm((f) => ({ ...f, [key]: value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setResult(null);
    try {
      const resp = await api.adminCreateUser({
        ...form,
        password: passwordRef.current?.value ?? '',
        handle: form.handle.toLowerCase().trim(),
        email: form.email.toLowerCase().trim(),
        skip_email: true,
      });
      setResult({ ok: true, message: `User created: @${resp.handle} (${resp.user_id})` });
      setForm({ email: '', handle: '', display_name: '', bio: '', role: 'user', verified: false, official: false });
      if (passwordRef.current) passwordRef.current.value = '';
    } catch (e: any) {
      setResult({ ok: false, message: e.message || String(e) });
    }
    setLoading(false);
  };

  return (
    <form onSubmit={handleSubmit} className="bg-white rounded-xl border border-warm-300 p-6 max-w-3xl">
      <h2 className="text-lg font-semibold text-gray-900 mb-1">Create New User</h2>
      <p className="text-sm text-gray-500 mb-6">
        Admin-created accounts are immediately active — no email verification required.
      </p>

      <div className="grid grid-cols-2 gap-4 mb-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Email *</label>
          <input
            type="email"
            required
            value={form.email}
            onChange={(e) => update('email', e.target.value)}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
            placeholder="user@example.com"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Password *</label>
          <input
            ref={passwordRef}
            type="password"
            autoComplete="new-password"
            required
            minLength={8}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
            placeholder="Min 8 characters"
          />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 mb-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Handle *</label>
          <input
            type="text"
            required
            value={form.handle}
            onChange={(e) => update('handle', e.target.value)}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
            placeholder="username"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Display Name *</label>
          <input
            type="text"
            required
            value={form.display_name}
            onChange={(e) => update('display_name', e.target.value)}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
            placeholder="John Doe"
          />
        </div>
      </div>

      <div className="mb-4">
        <label className="block text-sm font-medium text-gray-700 mb-1">Bio</label>
        <textarea
          value={form.bio}
          onChange={(e) => update('bio', e.target.value)}
          rows={2}
          className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          placeholder="Optional bio"
        />
      </div>

      <div className="flex items-center gap-6 mb-6">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Role</label>
          <select
            value={form.role}
            onChange={(e) => update('role', e.target.value)}
            className="px-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500"
          >
            <option value="user">User</option>
            <option value="admin">Admin</option>
            <option value="moderator">Moderator</option>
          </select>
        </div>
        <label className="flex items-center gap-2 cursor-pointer mt-5">
          <input
            type="checkbox"
            checked={form.verified}
            onChange={(e) => update('verified', e.target.checked)}
            className="w-4 h-4 rounded border-warm-300 text-brand-500 focus:ring-brand-500"
          />
          <span className="text-sm text-gray-700">Verified</span>
        </label>
        <label className="flex items-center gap-2 cursor-pointer mt-5">
          <input
            type="checkbox"
            checked={form.official}
            onChange={(e) => update('official', e.target.checked)}
            className="w-4 h-4 rounded border-warm-300 text-brand-500 focus:ring-brand-500"
          />
          <span className="text-sm text-gray-700">Official</span>
        </label>
      </div>

      <button
        type="submit"
        disabled={loading}
        className="flex items-center gap-2 px-6 py-2.5 bg-brand-500 text-white rounded-lg text-sm font-medium hover:bg-brand-600 disabled:opacity-50 transition-colors"
      >
        <UserPlus className="w-4 h-4" />
        {loading ? 'Creating...' : 'Create User'}
      </button>

      {result && (
        <div className={`mt-4 p-3 rounded-lg text-sm flex items-start gap-2 ${result.ok ? 'bg-green-50 text-green-800 border border-green-200' : 'bg-red-50 text-red-800 border border-red-200'}`}>
          {result.ok ? <CheckCircle className="w-4 h-4 mt-0.5 flex-shrink-0" /> : <AlertCircle className="w-4 h-4 mt-0.5 flex-shrink-0" />}
          <span className="break-all">{result.message}</span>
        </div>
      )}
    </form>
  );
}

// ─── Import Content Panel ─────────────────────────────
function ImportContentPanel() {
  const [authorId, setAuthorId] = useState('');
  const [contentType, setContentType] = useState('post');
  const [inputMode, setInputMode] = useState<'links' | 'csv'>('links');
  const [inputText, setInputText] = useState('');
  const [sharedBody, setSharedBody] = useState('');
  const [isNsfw, setIsNsfw] = useState(false);
  const [visibility, setVisibility] = useState('public');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<any>(null);

  const parseItems = (): any[] => {
    const raw = inputText.trim();
    if (!raw) return [];

    if (inputMode === 'links') {
      return raw
        .split('\n')
        .map((l) => l.trim())
        .filter((l) => l.length > 0)
        .map((url) => ({
          body: sharedBody.trim(),
          media_url: url,
          is_nsfw: isNsfw,
          visibility,
          tags: [],
        }));
    } else {
      const lines = raw.split('\n').filter((l) => l.trim().length > 0);
      const startIdx = lines.length > 0 && lines[0].toLowerCase().includes('body') ? 1 : 0;
      return lines.slice(startIdx).map((line) => {
        const cols = parseCsvLine(line);
        return {
          body: cols[0] || '',
          media_url: cols[1] || '',
          thumbnail_url: cols[2] || '',
          tags: cols[3] ? cols[3].split(';').filter((t) => t) : [],
          is_nsfw: cols[4] ? cols[4].toLowerCase() === 'true' : isNsfw,
          visibility: cols[5] || visibility,
        };
      });
    }
  };

  const handleImport = async () => {
    if (!authorId.trim()) {
      setResult({ error: 'Author is required' });
      return;
    }
    const items = parseItems();
    if (items.length === 0) {
      setResult({ error: 'No items to import' });
      return;
    }

    setLoading(true);
    setResult(null);
    try {
      const resp = await api.adminImportContent({
        author_id: authorId.trim(),
        content_type: contentType,
        items,
      });
      setResult(resp);
    } catch (e: any) {
      setResult({ error: e.message || String(e) });
    }
    setLoading(false);
  };

  const itemCount = parseItems().length;

  return (
    <div className="bg-white rounded-xl border border-warm-300 p-6 max-w-4xl">
      <h2 className="text-lg font-semibold text-gray-900 mb-1">Import Content</h2>
      <p className="text-sm text-gray-500 mb-6">
        Import posts, quips, or beacons from direct R2 links or CSV data.
      </p>

      {/* Author + Type */}
      <div className="grid grid-cols-3 gap-4 mb-4">
        <div className="col-span-2">
          <UserSearch value={authorId} onChange={(id) => setAuthorId(id)} />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Content Type</label>
          <select
            value={contentType}
            onChange={(e) => setContentType(e.target.value)}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500"
          >
            <option value="post">Post (image)</option>
            <option value="quip">Quip (video)</option>
            <option value="beacon">Beacon</option>
          </select>
        </div>
      </div>

      {/* Input mode + flags */}
      <div className="flex items-center gap-4 mb-4">
        <div className="flex bg-warm-200 rounded-lg p-0.5">
          <button
            onClick={() => setInputMode('links')}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
              inputMode === 'links' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600'
            }`}
          >
            <Link2 className="w-3.5 h-3.5" />
            Plain Links
          </button>
          <button
            onClick={() => setInputMode('csv')}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
              inputMode === 'csv' ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600'
            }`}
          >
            <FileText className="w-3.5 h-3.5" />
            CSV
          </button>
        </div>

        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={isNsfw}
            onChange={(e) => setIsNsfw(e.target.checked)}
            className="w-4 h-4 rounded border-warm-300 text-brand-500 focus:ring-brand-500"
          />
          <span className="text-sm text-gray-700">NSFW</span>
        </label>

        <select
          value={visibility}
          onChange={(e) => setVisibility(e.target.value)}
          className="px-3 py-1.5 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500"
        >
          <option value="public">Public</option>
          <option value="followers">Followers</option>
          <option value="private">Private</option>
        </select>
      </div>

      {/* Shared body (links mode) */}
      {inputMode === 'links' && (
        <div className="mb-4">
          <label className="block text-sm font-medium text-gray-700 mb-1">Post Body (shared for all items)</label>
          <input
            type="text"
            value={sharedBody}
            onChange={(e) => setSharedBody(e.target.value)}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
            placeholder="Optional caption for all imported items"
          />
        </div>
      )}

      {/* Main input */}
      <div className="mb-2">
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {inputMode === 'links' ? 'Media URLs (one per line)' : 'CSV Data'}
        </label>
        <textarea
          value={inputText}
          onChange={(e) => setInputText(e.target.value)}
          rows={10}
          className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm font-mono focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
          placeholder={
            inputMode === 'links'
              ? 'https://media.sojorn.net/uploads/image1.jpg\nhttps://media.sojorn.net/uploads/video1.mp4'
              : 'body,media_url,thumbnail_url,tags,is_nsfw,visibility\nHello world,https://...,,,false,public'
          }
        />
      </div>

      <p className={`text-xs mb-4 ${itemCount === 0 ? 'text-amber-600' : 'text-green-600'}`}>
        {itemCount} item(s) detected
      </p>

      {/* Import button */}
      <button
        onClick={handleImport}
        disabled={loading}
        className="flex items-center gap-2 px-6 py-2.5 bg-brand-500 text-white rounded-lg text-sm font-medium hover:bg-brand-600 disabled:opacity-50 transition-colors"
      >
        <Upload className="w-4 h-4" />
        {loading ? 'Importing...' : 'Import Content'}
      </button>

      {/* Result */}
      {result && (
        <div className="mt-4">
          {result.error && !result.success ? (
            <div className="p-3 rounded-lg text-sm bg-red-50 text-red-800 border border-red-200 flex items-start gap-2">
              <AlertCircle className="w-4 h-4 mt-0.5 flex-shrink-0" />
              <span>{result.error}</span>
            </div>
          ) : (
            <div className="p-4 rounded-lg bg-green-50 border border-green-200">
              <div className="flex items-center gap-2 mb-2">
                <CheckCircle className="w-4 h-4 text-green-600" />
                <span className="text-sm font-medium text-green-800">{result.message}</span>
              </div>
              <p className="text-xs text-green-700 mb-2">
                Success: {result.success} &nbsp;|&nbsp; Failures: {result.failures}
              </p>

              {result.errors?.length > 0 && (
                <div className="mb-2">
                  <p className="text-xs font-semibold text-red-700 mb-1">Errors:</p>
                  {result.errors.map((err: string, i: number) => (
                    <p key={i} className="text-xs text-red-600">{err}</p>
                  ))}
                </div>
              )}

              {result.created?.length > 0 && (
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <p className="text-xs font-semibold text-green-700">Post IDs:</p>
                    <button
                      onClick={() => {
                        navigator.clipboard.writeText(result.created.join('\n'));
                      }}
                      className="text-xs text-brand-500 hover:text-brand-600 flex items-center gap-1"
                    >
                      <Copy className="w-3 h-3" /> Copy
                    </button>
                  </div>
                  <div className="max-h-32 overflow-y-auto">
                    {result.created.slice(0, 20).map((id: string) => (
                      <p key={id} className="text-xs font-mono text-gray-600">{id}</p>
                    ))}
                    {result.created.length > 20 && (
                      <p className="text-xs text-gray-500">...and {result.created.length - 20} more</p>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Social Import Panel ──────────────────────────────
type SocialItem = {
  id: string;
  title: string;
  description: string;
  url: string;
  thumbnail_url: string;
  media_type: string;
  duration: number;
  upload_date: string;
  view_count: number;
  like_count: number;
  platform: string;
  imported: boolean;
  imported_at?: string;
  imported_as_id?: string;
};

type ItemOverrides = {
  title: string;
  description: string;
  importAs: 'post' | 'quip';
};

// ─── Platform Cookie Manager ─────────────────────────
type CookieStatus = {
  platform: string;
  has_cookie: boolean;
  file_name?: string;
  file_size?: number;
  updated_at?: string;
};

function CookieManager() {
  const [cookies, setCookies] = useState<CookieStatus[]>([]);
  const [loading, setLoading] = useState(true);
  const [expanded, setExpanded] = useState(false);
  const [testing, setTesting] = useState<string | null>(null);
  const [testResult, setTestResult] = useState<Record<string, { valid: boolean; message: string } | null>>({});
  const [uploading, setUploading] = useState<string | null>(null);
  const fileInputRefs = useRef<Record<string, HTMLInputElement | null>>({});

  const fetchCookies = useCallback(async () => {
    try {
      const data = await api.listSocialCookies();
      setCookies(data.cookies || []);
    } catch { /* ignore */ }
    setLoading(false);
  }, []);

  useEffect(() => { fetchCookies(); }, [fetchCookies]);

  const handleUpload = async (platform: string, file: File) => {
    setUploading(platform);
    setTestResult((prev) => ({ ...prev, [platform]: null }));
    try {
      await api.uploadSocialCookies(platform, file);
      await fetchCookies();
    } catch (e: any) {
      setTestResult((prev) => ({ ...prev, [platform]: { valid: false, message: e.message } }));
    }
    setUploading(null);
  };

  const handleDelete = async (platform: string) => {
    if (!confirm(`Remove cookies for ${platform}?`)) return;
    try {
      await api.deleteSocialCookies(platform);
      setTestResult((prev) => ({ ...prev, [platform]: null }));
      await fetchCookies();
    } catch { /* ignore */ }
  };

  const handleTest = async (platform: string) => {
    setTesting(platform);
    setTestResult((prev) => ({ ...prev, [platform]: null }));
    try {
      const data = await api.testSocialCookies(platform);
      setTestResult((prev) => ({ ...prev, [platform]: { valid: data.valid, message: data.message || data.error || '' } }));
    } catch (e: any) {
      setTestResult((prev) => ({ ...prev, [platform]: { valid: false, message: e.message } }));
    }
    setTesting(null);
  };

  const hasCookies = cookies.some((c) => c.has_cookie);

  return (
    <div className="mb-5 border border-warm-300 rounded-lg overflow-hidden">
      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center justify-between px-4 py-3 bg-warm-50 hover:bg-warm-100 transition-colors text-left"
      >
        <div className="flex items-center gap-2">
          <Cookie className="w-4 h-4 text-gray-500" />
          <span className="text-sm font-medium text-gray-700">Platform Cookies</span>
          {hasCookies && (
            <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full">
              {cookies.filter((c) => c.has_cookie).length} configured
            </span>
          )}
          {!hasCookies && !loading && (
            <span className="text-xs text-gray-400">Required for Facebook &amp; Instagram</span>
          )}
        </div>
        {expanded ? <ChevronDown className="w-4 h-4 text-gray-400" /> : <ChevronRight className="w-4 h-4 text-gray-400" />}
      </button>

      {expanded && (
        <div className="p-4 border-t border-warm-200">
          <p className="text-xs text-gray-500 mb-3">
            Facebook and Instagram require login cookies to access content. Export cookies from your browser using an extension like{' '}
            <strong>Get cookies.txt LOCALLY</strong>, then upload the file here.
          </p>

          {loading ? (
            <div className="flex items-center gap-2 text-sm text-gray-400"><Loader2 className="w-4 h-4 animate-spin" /> Loading...</div>
          ) : (
            <div className="space-y-2">
              {cookies.map((c) => (
                <div key={c.platform} className="flex items-center gap-3 py-2 px-3 rounded-lg bg-warm-50">
                  <span className="text-sm font-medium capitalize w-24">{c.platform}</span>

                  {c.has_cookie ? (
                    <>
                      <Shield className="w-4 h-4 text-green-500" />
                      <span className="text-xs text-green-700">
                        Cookies loaded ({(c.file_size! / 1024).toFixed(1)} KB)
                      </span>
                      {c.updated_at && (
                        <span className="text-[10px] text-gray-400">
                          Updated {new Date(c.updated_at).toLocaleDateString()}
                        </span>
                      )}
                      <div className="ml-auto flex items-center gap-1">
                        <button
                          type="button"
                          onClick={() => handleTest(c.platform)}
                          disabled={testing === c.platform}
                          className="text-xs px-2 py-1 rounded bg-brand-50 text-brand-600 hover:bg-brand-100 disabled:opacity-50 flex items-center gap-1"
                        >
                          {testing === c.platform ? <Loader2 className="w-3 h-3 animate-spin" /> : <TestTube className="w-3 h-3" />}
                          Test
                        </button>
                        <button
                          type="button"
                          onClick={() => fileInputRefs.current[c.platform]?.click()}
                          disabled={uploading === c.platform}
                          className="text-xs px-2 py-1 rounded bg-warm-200 text-gray-600 hover:bg-warm-300 disabled:opacity-50"
                        >
                          Replace
                        </button>
                        <button
                          type="button"
                          title={`Delete cookies for ${c.platform}`}
                          onClick={() => handleDelete(c.platform)}
                          className="text-xs px-2 py-1 rounded bg-red-50 text-red-600 hover:bg-red-100 flex items-center gap-1"
                        >
                          <Trash2 className="w-3 h-3" />
                        </button>
                      </div>
                    </>
                  ) : (
                    <>
                      <span className="text-xs text-gray-400">No cookies</span>
                      <div className="ml-auto">
                        <button
                          type="button"
                          onClick={() => fileInputRefs.current[c.platform]?.click()}
                          disabled={uploading === c.platform}
                          className="text-xs px-3 py-1 rounded bg-brand-500 text-white hover:bg-brand-600 disabled:opacity-50 flex items-center gap-1"
                        >
                          {uploading === c.platform ? <Loader2 className="w-3 h-3 animate-spin" /> : <Upload className="w-3 h-3" />}
                          Upload cookies.txt
                        </button>
                      </div>
                    </>
                  )}

                  <input
                    type="file"
                    accept=".txt,.cookies"
                    title={`Upload cookies file for ${c.platform}`}
                    className="hidden"
                    ref={(el) => { fileInputRefs.current[c.platform] = el; }}
                    onChange={(e) => {
                      const f = e.target.files?.[0];
                      if (f) handleUpload(c.platform, f);
                      e.target.value = '';
                    }}
                  />

                  {testResult[c.platform] && (
                    <div className={`text-xs ${testResult[c.platform]!.valid ? 'text-green-600' : 'text-red-600'}`}>
                      {testResult[c.platform]!.valid ? <Check className="w-3 h-3 inline" /> : <X className="w-3 h-3 inline" />}{' '}
                      {testResult[c.platform]!.message}
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function SocialImportPanel() {
  const [profileUrl, setProfileUrl] = useState('');
  const [authorId, setAuthorId] = useState('');
  const [fetching, setFetching] = useState(false);
  const [items, setItems] = useState<SocialItem[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [overrides, setOverrides] = useState<Record<string, ItemOverrides>>({});
  const [platform, setPlatform] = useState('');
  const [error, setError] = useState('');
  const [importing, setImporting] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState<Record<string, 'pending' | 'downloading' | 'done' | 'error'>>({});
  const [downloadedUrls, setDownloadedUrls] = useState<Record<string, string>>({});
  const [importResult, setImportResult] = useState<any>(null);
  const [fetchLimit, setFetchLimit] = useState(20);
  const [dateAfter, setDateAfter] = useState('');
  const [dateBefore, setDateBefore] = useState('');
  const [editingItem, setEditingItem] = useState<string | null>(null);

  const handleFetch = async () => {
    if (!profileUrl.trim()) return;
    setFetching(true);
    setError('');
    setItems([]);
    setSelected(new Set());
    setOverrides({});
    setImportResult(null);
    setDownloadProgress({});
    setDownloadedUrls({});
    try {
      const data = await api.fetchSocialContent(profileUrl.trim(), fetchLimit, dateAfter || undefined, dateBefore || undefined);
      setItems(data.items || []);
      setPlatform(data.platform || '');
      // Initialize overrides with original data
      const defaults: Record<string, ItemOverrides> = {};
      (data.items || []).forEach((item: SocialItem) => {
        defaults[item.id] = {
          title: item.title || '',
          description: item.description || '',
          importAs: item.media_type === 'video' ? 'quip' : 'post',
        };
      });
      setOverrides(defaults);
    } catch (e: any) {
      setError(e.message || 'Failed to fetch content');
    }
    setFetching(false);
  };

  const toggleSelect = (id: string) => {
    if (importing) return;
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const newItems = items.filter((i) => !i.imported);
  const importedItems = items.filter((i) => i.imported);

  const selectAll = () => {
    if (selected.size === newItems.length) {
      setSelected(new Set());
    } else {
      // Select only new (not-yet-imported) items by default
      setSelected(new Set(newItems.map((i) => i.id)));
    }
  };

  const selectAllIncluding = () => {
    setSelected(new Set(items.map((i) => i.id)));
  };

  const updateOverride = (id: string, field: keyof ItemOverrides, value: string) => {
    setOverrides((prev) => ({
      ...prev,
      [id]: { ...prev[id], [field]: value },
    }));
  };

  const handleImport = async () => {
    if (!authorId.trim()) { setError('Select an author first'); return; }
    if (selected.size === 0) { setError('Select at least one item'); return; }

    setImporting(true);
    setError('');
    setImportResult(null);

    const selectedItems = items.filter((i) => selected.has(i.id));

    // Step 1: Download each selected item
    const progress: Record<string, 'pending' | 'downloading' | 'done' | 'error'> = {};
    const urls: Record<string, string> = {};
    selectedItems.forEach((i) => { progress[i.id] = 'pending'; });
    setDownloadProgress({ ...progress });

    for (const item of selectedItems) {
      progress[item.id] = 'downloading';
      setDownloadProgress({ ...progress });
      try {
        const result = await api.downloadSocialMedia(item.url, platform, item.media_type);
        urls[item.id] = result.media_url || result.local_path || item.url;
        progress[item.id] = 'done';
      } catch {
        urls[item.id] = item.url;
        progress[item.id] = 'error';
      }
      setDownloadProgress({ ...progress });
      setDownloadedUrls({ ...urls });
    }

    // Step 2: Group by content type and import, using overrides for body text
    const postItems = selectedItems.filter((i) => overrides[i.id]?.importAs === 'post');
    const quipItems = selectedItems.filter((i) => overrides[i.id]?.importAs !== 'post');

    let totalSuccess = 0;
    let totalFailures = 0;
    const allErrors: string[] = [];
    const allCreated: string[] = [];

    for (const [type, batch] of [['post', postItems], ['quip', quipItems]] as const) {
      if (batch.length === 0) continue;
      try {
        const resp = await api.adminImportContent({
          author_id: authorId.trim(),
          content_type: type,
          items: batch.map((item) => {
            const ov = overrides[item.id];
            // Use override description first, then title, then original values
            const body = (ov?.description || ov?.title || item.description || item.title || '').trim();
            return {
              body,
              media_url: urls[item.id] || item.url,
              thumbnail_url: item.thumbnail_url,
              duration_ms: item.duration ? item.duration * 1000 : undefined,
              visibility: 'public',
              // Social import tracking
              original_date: item.upload_date || undefined,
              external_id: item.id,
              external_url: item.url,
              platform: item.platform || platform,
            };
          }),
        });
        totalSuccess += resp.success || 0;
        totalFailures += resp.failures || 0;
        if (resp.errors) allErrors.push(...resp.errors);
        if (resp.created) allCreated.push(...resp.created);
        if (resp.updated) allCreated.push(...resp.updated);
      } catch (e: any) {
        allErrors.push(`${type} batch failed: ${e.message}`);
        totalFailures += batch.length;
      }
    }

    setImportResult({
      success: totalSuccess,
      failures: totalFailures,
      errors: allErrors,
      created: allCreated,
      message: `Imported ${totalSuccess} items`,
    });
    setImporting(false);
    setSelected(new Set());

    // Re-fetch to update imported status
    if (profileUrl.trim()) {
      try {
        const data = await api.fetchSocialContent(profileUrl.trim(), fetchLimit, dateAfter || undefined, dateBefore || undefined);
        setItems(data.items || []);
      } catch { /* ignore refresh errors */ }
    }
  };

  const formatDuration = (s: number) => {
    if (!s) return '';
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };

  const formatCount = (n: number) => {
    if (!n) return '0';
    if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M';
    if (n >= 1000) return (n / 1000).toFixed(1) + 'K';
    return String(n);
  };

  return (
    <div className="bg-white rounded-xl border border-warm-300 p-6 max-w-6xl">
      <h2 className="text-lg font-semibold text-gray-900 mb-1">Social Media Import</h2>
      <p className="text-sm text-gray-500 mb-6">
        Fetch public content from YouTube, TikTok, Facebook, or Instagram. Select items, edit titles and descriptions, then import as posts or quips. Requires <code className="text-xs bg-warm-100 px-1 rounded">yt-dlp</code> on the server.
      </p>

      <CookieManager />

      {/* Profile URL + Author */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Profile / Channel URL *</label>
          <div className="flex gap-2">
            <input
              type="url"
              value={profileUrl}
              onChange={(e) => setProfileUrl(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleFetch()}
              className="flex-1 px-3 py-2 border border-warm-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
              placeholder="https://www.youtube.com/@channel or https://tiktok.com/@user"
            />
            <div className="flex items-center gap-2">
              <input
                type="number"
                value={fetchLimit}
                onChange={(e) => setFetchLimit(Math.max(1, Number(e.target.value) || 20))}
                className="px-2 py-2 border border-warm-300 rounded-lg text-sm w-16 text-center"
                title="Number of items to fetch"
                min={1}
                max={500}
              />
              <button
                type="button"
                onClick={handleFetch}
                disabled={fetching || !profileUrl.trim()}
                className="flex items-center gap-2 px-4 py-2 bg-brand-500 text-white rounded-lg text-sm font-medium hover:bg-brand-600 disabled:opacity-50 transition-colors whitespace-nowrap"
              >
                {fetching ? <Loader2 className="w-4 h-4 animate-spin" /> : <Search className="w-4 h-4" />}
                {fetching ? 'Fetching...' : 'Fetch'}
              </button>
            </div>
          </div>
        </div>
        <div>
          <UserSearch value={authorId} onChange={(id) => setAuthorId(id)} />
        </div>
      </div>

      {/* Date Range Filter */}
      <div className="flex items-center gap-3 mb-4">
        <div className="flex items-center gap-2">
          <label className="text-xs font-medium text-gray-500 whitespace-nowrap">From</label>
          <input
            type="date"
            value={dateAfter}
            onChange={(e) => setDateAfter(e.target.value)}
            title="Filter content uploaded after this date"
            className="px-2 py-1.5 border border-warm-300 rounded-lg text-sm focus:ring-1 focus:ring-brand-500"
          />
        </div>
        <div className="flex items-center gap-2">
          <label className="text-xs font-medium text-gray-500 whitespace-nowrap">To</label>
          <input
            type="date"
            value={dateBefore}
            onChange={(e) => setDateBefore(e.target.value)}
            title="Filter content uploaded before this date"
            className="px-2 py-1.5 border border-warm-300 rounded-lg text-sm focus:ring-1 focus:ring-brand-500"
          />
        </div>
        {(dateAfter || dateBefore) && (
          <button
            type="button"
            onClick={() => { setDateAfter(''); setDateBefore(''); }}
            className="text-xs text-gray-500 hover:text-gray-700"
          >
            Clear dates
          </button>
        )}
        <span className="text-[10px] text-gray-400">Leave blank for no date filter</span>
      </div>

      {error && (
        <div className="mb-4 p-3 rounded-lg text-sm bg-red-50 text-red-800 border border-red-200 flex items-start gap-2">
          <AlertCircle className="w-4 h-4 mt-0.5 flex-shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* Content Grid */}
      {items.length > 0 && (
        <>
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-3">
              <button
                type="button"
                onClick={selectAll}
                className="text-sm text-brand-600 hover:text-brand-700 font-medium"
              >
                {selected.size >= newItems.length && selected.size > 0 ? 'Deselect All' : `Select New (${newItems.length})`}
              </button>
              {importedItems.length > 0 && (
                <button
                  type="button"
                  onClick={selectAllIncluding}
                  className="text-sm text-gray-500 hover:text-gray-700 font-medium"
                >
                  Select All ({items.length})
                </button>
              )}
              <span className="text-sm text-gray-500">
                {selected.size} selected
              </span>
              {importedItems.length > 0 && (
                <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full font-medium">
                  {importedItems.length} already imported
                </span>
              )}
              {platform && (
                <span className="text-xs bg-warm-200 px-2 py-0.5 rounded-full text-gray-600 capitalize">{platform}</span>
              )}
            </div>

            <button
              type="button"
              onClick={handleImport}
              disabled={importing || selected.size === 0 || !authorId}
              className="flex items-center gap-2 px-5 py-2 bg-brand-500 text-white rounded-lg text-sm font-medium hover:bg-brand-600 disabled:opacity-50 transition-colors"
            >
              {importing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Download className="w-4 h-4" />}
              {importing ? 'Importing...' : `Import ${selected.size} Items`}
            </button>
          </div>

          <div className="space-y-2 max-h-[700px] overflow-y-auto">
            {items.map((item) => {
              const isSelected = selected.has(item.id);
              const dlStatus = downloadProgress[item.id];
              const ov = overrides[item.id];
              const isEditing = editingItem === item.id;
              return (
                <div
                  key={item.id}
                  className={`rounded-lg border-2 overflow-hidden transition-all ${
                    isSelected
                      ? 'border-brand-500 bg-brand-50/30'
                      : item.imported
                        ? 'border-green-200 bg-green-50/30'
                        : 'border-warm-200 hover:border-warm-400'
                  }`}
                >
                  <div className="flex gap-3 p-3">
                    {/* Thumbnail + checkbox */}
                    <div
                      className="relative w-40 flex-shrink-0 cursor-pointer"
                      onClick={() => toggleSelect(item.id)}
                    >
                      <div className="relative aspect-video bg-warm-100 rounded-md overflow-hidden">
                        {item.thumbnail_url ? (
                          <img src={item.thumbnail_url} alt="" className="w-full h-full object-cover" />
                        ) : (
                          <div className="w-full h-full flex items-center justify-center text-gray-400">
                            {item.media_type === 'video' ? <Play className="w-6 h-6" /> : <ImageIcon className="w-6 h-6" />}
                          </div>
                        )}
                        {item.duration > 0 && (
                          <span className="absolute bottom-1 right-1 bg-black/75 text-white text-[10px] px-1 py-0.5 rounded">
                            {formatDuration(item.duration)}
                          </span>
                        )}
                        <div className={`absolute top-1.5 left-1.5 w-5 h-5 rounded border-2 flex items-center justify-center transition-colors ${
                          isSelected ? 'bg-brand-500 border-brand-500' : 'bg-white/80 border-gray-400'
                        }`}>
                          {isSelected && <Check className="w-3 h-3 text-white" />}
                        </div>
                        {dlStatus && (
                          <div className={`absolute top-1.5 right-1.5 w-5 h-5 rounded-full flex items-center justify-center ${
                            dlStatus === 'downloading' ? 'bg-yellow-400' :
                            dlStatus === 'done' ? 'bg-green-500' :
                            dlStatus === 'error' ? 'bg-red-500' : 'bg-gray-300'
                          }`}>
                            {dlStatus === 'downloading' && <Loader2 className="w-3 h-3 text-white animate-spin" />}
                            {dlStatus === 'done' && <Check className="w-3 h-3 text-white" />}
                            {dlStatus === 'error' && <X className="w-3 h-3 text-white" />}
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Content info */}
                    <div className="flex-1 min-w-0">
                      {isEditing ? (
                        <div className="space-y-2" onClick={(e) => e.stopPropagation()}>
                          <div>
                            <label className="block text-[10px] font-medium text-gray-500 mb-0.5">Title</label>
                            <input
                              type="text"
                              value={ov?.title || ''}
                              onChange={(e) => updateOverride(item.id, 'title', e.target.value)}
                              className="w-full px-2 py-1.5 border border-warm-300 rounded text-sm focus:ring-1 focus:ring-brand-500 focus:border-brand-500"
                              placeholder="Title for this content"
                            />
                          </div>
                          <div>
                            <label className="block text-[10px] font-medium text-gray-500 mb-0.5">Description / Caption</label>
                            <textarea
                              value={ov?.description || ''}
                              onChange={(e) => updateOverride(item.id, 'description', e.target.value)}
                              rows={2}
                              className="w-full px-2 py-1.5 border border-warm-300 rounded text-sm focus:ring-1 focus:ring-brand-500 focus:border-brand-500"
                              placeholder="Caption that will appear on the post"
                            />
                          </div>
                          <div className="flex items-center gap-3">
                            <select
                              value={ov?.importAs || 'quip'}
                              onChange={(e) => updateOverride(item.id, 'importAs', e.target.value)}
                              className="px-2 py-1 border border-warm-300 rounded text-xs"
                              title="Import as"
                            >
                              <option value="quip">Import as Quip (video)</option>
                              <option value="post">Import as Post (image)</option>
                            </select>
                            <button
                              type="button"
                              onClick={() => setEditingItem(null)}
                              className="text-xs text-brand-600 hover:text-brand-700 font-medium"
                            >
                              Done
                            </button>
                          </div>
                        </div>
                      ) : (
                        <>
                          <div className="flex items-start justify-between gap-2">
                            <div className="min-w-0">
                              <p className="text-sm font-medium text-gray-900 truncate">
                                {ov?.title || item.title || item.description || 'Untitled'}
                              </p>
                              {(ov?.description || item.description) && (ov?.description || item.description) !== (ov?.title || item.title) && (
                                <p className="text-xs text-gray-500 line-clamp-2 mt-0.5">
                                  {ov?.description || item.description}
                                </p>
                              )}
                            </div>
                            {isSelected && (
                              <button
                                type="button"
                                onClick={(e) => { e.stopPropagation(); setEditingItem(item.id); }}
                                className="text-xs text-brand-500 hover:text-brand-600 font-medium whitespace-nowrap flex-shrink-0"
                              >
                                Edit
                              </button>
                            )}
                          </div>
                          <div className="flex items-center gap-3 mt-1.5 flex-wrap">
                            <div className="flex items-center gap-2 text-[10px] text-gray-500">
                              {item.view_count > 0 && <span>{formatCount(item.view_count)} views</span>}
                              {item.like_count > 0 && <span>{formatCount(item.like_count)} likes</span>}
                              {item.upload_date && <span>{item.upload_date}</span>}
                            </div>
                            {item.imported && (
                              <span className="text-[10px] px-1.5 py-0.5 rounded-full font-medium bg-green-100 text-green-700" title={item.imported_at ? `Imported ${new Date(item.imported_at).toLocaleDateString()}` : 'Already imported'}>
                                {isSelected ? 'Re-import' : 'Imported'}
                              </span>
                            )}
                            {isSelected && (
                              <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-medium ${
                                ov?.importAs === 'post'
                                  ? 'bg-blue-100 text-blue-700'
                                  : 'bg-purple-100 text-purple-700'
                              }`}>
                                {ov?.importAs === 'post' ? 'Post' : 'Quip'}
                              </span>
                            )}
                            {item.url && (
                              <a
                                href={item.url}
                                target="_blank"
                                rel="noopener noreferrer"
                                onClick={(e) => e.stopPropagation()}
                                className="text-[10px] text-brand-500 hover:text-brand-600 flex items-center gap-0.5"
                              >
                                <ExternalLink className="w-2.5 h-2.5" /> Original
                              </a>
                            )}
                          </div>
                        </>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </>
      )}

      {/* Import Result */}
      {importResult && (
        <div className="mt-4 p-4 rounded-lg bg-green-50 border border-green-200">
          <div className="flex items-center gap-2 mb-2">
            <CheckCircle className="w-4 h-4 text-green-600" />
            <span className="text-sm font-medium text-green-800">{importResult.message}</span>
          </div>
          <p className="text-xs text-green-700 mb-2">
            Success: {importResult.success} | Failures: {importResult.failures}
          </p>
          {importResult.errors?.length > 0 && (
            <div className="mb-2">
              <p className="text-xs font-semibold text-red-700 mb-1">Errors:</p>
              {importResult.errors.map((err: string, i: number) => (
                <p key={i} className="text-xs text-red-600">{err}</p>
              ))}
            </div>
          )}
          {importResult.created?.length > 0 && (
            <div>
              <div className="flex items-center gap-2 mb-1">
                <p className="text-xs font-semibold text-green-700">Created IDs:</p>
                <button
                  type="button"
                  onClick={() => navigator.clipboard.writeText(importResult.created.join('\n'))}
                  className="text-xs text-brand-500 hover:text-brand-600 flex items-center gap-1"
                >
                  <Copy className="w-3 h-3" /> Copy
                </button>
              </div>
              <div className="max-h-24 overflow-y-auto">
                {importResult.created.slice(0, 10).map((id: string) => (
                  <p key={id} className="text-xs font-mono text-gray-600">{id}</p>
                ))}
                {importResult.created.length > 10 && (
                  <p className="text-xs text-gray-500">...and {importResult.created.length - 10} more</p>
                )}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
