'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { useState } from 'react';
import { UserPlus, Upload, AlertCircle, CheckCircle, Copy, FileText, Link2 } from 'lucide-react';

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

export default function ContentToolsPage() {
  const [activeTab, setActiveTab] = useState<'create-user' | 'import'>('create-user');

  return (
    <AdminShell>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Content Tools</h1>
        <p className="text-gray-500 mt-1">Create users and import content</p>
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
      </div>

      {activeTab === 'create-user' ? <CreateUserPanel /> : <ImportContentPanel />}
    </AdminShell>
  );
}

// ─── Create User Panel ────────────────────────────────
function CreateUserPanel() {
  const [form, setForm] = useState({
    email: '',
    password: '',
    handle: '',
    display_name: '',
    bio: '',
    role: 'user',
    verified: false,
    official: false,
  });
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
        handle: form.handle.toLowerCase().trim(),
        email: form.email.toLowerCase().trim(),
        skip_email: true,
      });
      setResult({ ok: true, message: `User created: @${resp.handle} (${resp.user_id})` });
      setForm({ email: '', password: '', handle: '', display_name: '', bio: '', role: 'user', verified: false, official: false });
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
            type="password"
            required
            minLength={8}
            value={form.password}
            onChange={(e) => update('password', e.target.value)}
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
      setResult({ error: 'Author ID is required' });
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
          <label className="block text-sm font-medium text-gray-700 mb-1">Author User ID *</label>
          <input
            type="text"
            value={authorId}
            onChange={(e) => setAuthorId(e.target.value)}
            className="w-full px-3 py-2 border border-warm-300 rounded-lg text-sm font-mono focus:ring-2 focus:ring-brand-500 focus:border-brand-500"
            placeholder="UUID of the user who owns these posts"
          />
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
                    <p key={i} className="text-xs text-red-600">• {err}</p>
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
