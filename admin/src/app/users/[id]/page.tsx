// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import { api } from '@/lib/api';
import { statusColor, formatDateTime } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { ArrowLeft, Shield, Ban, CheckCircle, XCircle, Star, RotateCcw, Pencil, UserPlus, UserMinus, Users, Save, X, RefreshCcw } from 'lucide-react';
import Link from 'next/link';

export default function UserDetailPage() {
  const params = useParams();
  const router = useRouter();
  const [user, setUser] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [showModal, setShowModal] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [customReason, setCustomReason] = useState(false);

  const reasonPresets: Record<string, string[]> = {
    banned: [
      'Hate speech or slurs',
      'Harassment or bullying',
      'Spam or scam activity',
      'Posting illegal content',
      'Impersonation',
      'Repeated violations after warnings',
      'Ban evasion (alt account)',
    ],
    suspended: [
      'Posting inappropriate content',
      'Minor harassment',
      'Spam behavior',
      'Violating community guidelines',
      'Cooling-off period after heated exchange',
    ],
    active: [
      'Appeal reviewed and approved',
      'Ban was issued in error',
      'Suspension period served',
      'User agreed to follow guidelines',
    ],
  };

  const fetchUser = () => {
    setLoading(true);
    api.getUser(params.id as string)
      .then(setUser)
      .catch(() => router.push('/users'))
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchUser(); }, [params.id]);

  const handleStatusChange = async (status: string) => {
    if (!reason.trim()) return;
    setActionLoading(true);
    try {
      await api.updateUserStatus(params.id as string, status, reason);
      setShowModal(null);
      setReason('');
      fetchUser();
    } catch (e: any) {
      alert(`Status change failed: ${e.message}`);
    }
    setActionLoading(false);
  };

  const handleRoleChange = async (role: string) => {
    setActionLoading(true);
    try {
      await api.updateUserRole(params.id as string, role);
      fetchUser();
    } catch (e: any) {
      alert(`Role change failed: ${e.message}`);
    }
    setActionLoading(false);
  };

  const handleVerification = async (isOfficial: boolean, isVerified: boolean) => {
    setActionLoading(true);
    try {
      await api.updateUserVerification(params.id as string, isOfficial, isVerified);
      fetchUser();
    } catch (e: any) {
      alert(`Verification update failed: ${e.message}`);
    }
    setActionLoading(false);
  };

  const handleResetStrikes = async () => {
    setActionLoading(true);
    try {
      await api.resetUserStrikes(params.id as string);
      fetchUser();
    } catch (e: any) {
      alert(`Reset strikes failed: ${e.message}`);
    }
    setActionLoading(false);
  };

  const handleResetFeedImpressions = async () => {
    if (!confirm('Reset this user\'s feed impression history? They will see previously-seen posts again.')) return;
    setActionLoading(true);
    try {
      const result = await api.resetFeedImpressions(params.id as string);
      alert(`Feed impressions reset. ${result.deleted ?? 0} records cleared.`);
    } catch (e: any) {
      alert(`Reset failed: ${e.message}`);
    }
    setActionLoading(false);
  };

  return (
    <AdminShell>
      <Link href="/users" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-4">
        <ArrowLeft className="w-4 h-4" /> Back to Users
      </Link>

      {loading ? (
        <div className="card p-8 animate-pulse"><div className="h-6 bg-warm-300 rounded w-40" /></div>
      ) : user ? (
        <div className="space-y-6">
          {/* Header */}
          <div className="card p-6">
            <div className="flex items-start justify-between">
              <div className="flex items-center gap-4">
                <div className="w-16 h-16 bg-brand-100 rounded-2xl flex items-center justify-center text-brand-600 text-xl font-bold">
                  {(user.handle || user.email || '?')[0].toUpperCase()}
                </div>
                <div>
                  <h1 className="text-xl font-bold text-gray-900">{user.display_name || user.handle || '—'}</h1>
                  <p className="text-sm text-gray-500">@{user.handle || '—'} · {user.email}</p>
                  <div className="flex items-center gap-2 mt-2">
                    <span className={`badge ${statusColor(user.status)}`}>{user.status}</span>
                    <span className={`badge ${user.role === 'admin' ? 'bg-purple-100 text-purple-700' : user.role === 'moderator' ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600'}`}>
                      {user.role || 'user'}
                    </span>
                    {user.is_official && <span className="badge bg-blue-100 text-blue-700">Official</span>}
                    {user.is_verified && <span className="badge bg-green-100 text-green-700">Verified</span>}
                    {user.is_private && <span className="badge bg-gray-100 text-gray-600">Private</span>}
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Stats Grid */}
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4">
            {[
              { label: 'Followers', value: user.follower_count },
              { label: 'Following', value: user.following_count },
              { label: 'Posts', value: user.post_count },
              { label: 'Strikes', value: user.strikes },
              { label: 'Violations', value: user.violation_count },
              { label: 'Reports', value: user.report_count },
            ].map((s) => (
              <div key={s.label} className="card p-4 text-center">
                <p className="text-2xl font-bold text-gray-900">{s.value ?? 0}</p>
                <p className="text-xs text-gray-500 mt-1">{s.label}</p>
              </div>
            ))}
          </div>

          {/* Details */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <div className="card p-5">
              <h3 className="text-sm font-semibold text-gray-700 mb-3">Profile Details</h3>
              <dl className="space-y-2 text-sm">
                {[
                  ['Bio', user.bio],
                  ['Location', user.location],
                  ['Website', user.website],
                  ['Country', user.origin_country],
                  ['Beacon Enabled', user.beacon_enabled ? 'Yes' : 'No'],
                  ['Onboarding Complete', user.has_completed_onboarding ? 'Yes' : 'No'],
                  ['Joined', user.created_at ? formatDateTime(user.created_at) : '—'],
                  ['Last Login', user.last_login ? formatDateTime(user.last_login) : 'Never'],
                ].map(([label, value]) => (
                  <div key={label as string} className="flex justify-between">
                    <dt className="text-gray-500">{label}</dt>
                    <dd className="text-gray-900 font-medium text-right max-w-xs truncate">{value || '—'}</dd>
                  </div>
                ))}
              </dl>
            </div>

            {/* Actions */}
            <div className="card p-5">
              <h3 className="text-sm font-semibold text-gray-700 mb-3">Admin Actions</h3>
              <div className="space-y-3">
                {/* Status changes */}
                <div>
                  <p className="text-xs font-medium text-gray-500 mb-2">Account Status</p>
                  <div className="flex flex-wrap gap-2">
                    {user.status !== 'active' && (
                      <button onClick={() => setShowModal('active')} className="btn-primary text-xs py-1.5 flex items-center gap-1">
                        <CheckCircle className="w-3.5 h-3.5" /> Activate
                      </button>
                    )}
                    {user.status !== 'suspended' && (
                      <button onClick={() => setShowModal('suspended')} className="bg-orange-500 text-white px-3 py-1.5 rounded-lg text-xs font-medium hover:bg-orange-600 flex items-center gap-1">
                        <XCircle className="w-3.5 h-3.5" /> Suspend
                      </button>
                    )}
                    {user.status !== 'banned' && (
                      <button onClick={() => setShowModal('banned')} className="btn-danger text-xs py-1.5 flex items-center gap-1">
                        <Ban className="w-3.5 h-3.5" /> Ban
                      </button>
                    )}
                  </div>
                </div>

                {/* Role */}
                <div>
                  <p className="text-xs font-medium text-gray-500 mb-2">Role</p>
                  <select
                    className="input text-sm"
                    value={user.role || 'user'}
                    onChange={(e) => handleRoleChange(e.target.value)}
                    disabled={actionLoading}
                  >
                    <option value="user">User</option>
                    <option value="moderator">Moderator</option>
                    <option value="admin">Admin</option>
                  </select>
                </div>

                {/* Verification */}
                <div>
                  <p className="text-xs font-medium text-gray-500 mb-2">Verification</p>
                  <div className="flex gap-2">
                    <button
                      onClick={() => handleVerification(!user.is_official, user.is_verified ?? false)}
                      className={`text-xs py-1.5 px-3 rounded-lg font-medium flex items-center gap-1 ${user.is_official ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}
                      disabled={actionLoading}
                    >
                      <Star className="w-3.5 h-3.5" /> {user.is_official ? 'Remove Official' : 'Make Official'}
                    </button>
                    <button
                      onClick={() => handleVerification(user.is_official ?? false, !user.is_verified)}
                      className={`text-xs py-1.5 px-3 rounded-lg font-medium flex items-center gap-1 ${user.is_verified ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}
                      disabled={actionLoading}
                    >
                      <CheckCircle className="w-3.5 h-3.5" /> {user.is_verified ? 'Unverify' : 'Verify'}
                    </button>
                  </div>
                </div>

                {/* Reset Strikes */}
                {(user.strikes ?? 0) > 0 && (
                  <div>
                    <p className="text-xs font-medium text-gray-500 mb-2">Strikes</p>
                    <button onClick={handleResetStrikes} className="btn-secondary text-xs py-1.5 flex items-center gap-1" disabled={actionLoading}>
                      <RotateCcw className="w-3.5 h-3.5" /> Reset Strikes ({user.strikes})
                    </button>
                  </div>
                )}

                {/* Feed Impressions */}
                <div>
                  <p className="text-xs font-medium text-gray-500 mb-2">Feed History</p>
                  <button onClick={handleResetFeedImpressions} className="btn-secondary text-xs py-1.5 flex items-center gap-1" disabled={actionLoading}>
                    <RefreshCcw className="w-3.5 h-3.5" /> Reset Feed Impressions
                  </button>
                </div>

                {/* View Posts */}
                <div className="pt-2 border-t border-warm-300">
                  <Link href={`/posts?author_id=${user.id}`} className="text-brand-500 hover:text-brand-700 text-sm font-medium">
                    View User&apos;s Posts →
                  </Link>
                </div>
              </div>
            </div>
          </div>

          {/* Editable Profile */}
          <OfficialProfileEditor user={user} onSaved={fetchUser} />

          {/* Follower/Following Management */}
          <FollowManager userId={user.id} />
        </div>
      ) : (
        <div className="card p-8 text-center text-gray-500">User not found</div>
      )}

      {/* Status Change Modal */}
      {showModal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={() => { setShowModal(null); setReason(''); setCustomReason(false); }}>
          <div className="card p-6 w-full max-w-md mx-4" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-lg font-semibold text-gray-900 mb-1">
              {showModal === 'active' ? 'Activate' : showModal === 'suspended' ? 'Suspend' : 'Ban'} User
            </h3>
            <p className="text-sm text-gray-500 mb-4">Select a reason for this action.</p>

            <div className="space-y-2 mb-4">
              {(reasonPresets[showModal] || []).map((preset) => (
                <button
                  key={preset}
                  onClick={() => { setReason(preset); setCustomReason(false); }}
                  className={`w-full text-left px-3 py-2 rounded-lg text-sm border transition-colors ${
                    reason === preset && !customReason
                      ? 'border-brand-500 bg-brand-50 text-brand-700 font-medium'
                      : 'border-warm-300 hover:border-gray-400 text-gray-700'
                  }`}
                >
                  {preset}
                </button>
              ))}
              <button
                onClick={() => { setCustomReason(true); setReason(''); }}
                className={`w-full text-left px-3 py-2 rounded-lg text-sm border transition-colors ${
                  customReason
                    ? 'border-brand-500 bg-brand-50 text-brand-700 font-medium'
                    : 'border-warm-300 hover:border-gray-400 text-gray-700'
                }`}
              >
                Custom reason...
              </button>
            </div>

            {customReason && (
              <textarea
                className="input mb-4"
                rows={3}
                placeholder="Enter custom reason..."
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                autoFocus
              />
            )}

            <div className="flex gap-2 justify-end">
              <button onClick={() => { setShowModal(null); setReason(''); setCustomReason(false); }} className="btn-secondary text-sm">Cancel</button>
              <button
                onClick={() => handleStatusChange(showModal)}
                className={showModal === 'banned' ? 'btn-danger text-sm' : 'btn-primary text-sm'}
                disabled={actionLoading || !reason.trim()}
              >
                {actionLoading ? 'Processing...' : 'Confirm'}
              </button>
            </div>
          </div>
        </div>
      )}
    </AdminShell>
  );
}

// ─── Official Profile Editor ─────────────────────────
function OfficialProfileEditor({ user, onSaved }: { user: any; onSaved: () => void }) {
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; msg: string } | null>(null);
  const [form, setForm] = useState({
    handle: user.handle || '',
    display_name: user.display_name || '',
    bio: user.bio || '',
    avatar_url: user.avatar_url || '',
    cover_url: user.cover_url || '',
    location: user.location || '',
    website: user.website || '',
    origin_country: user.origin_country || '',
  });

  useEffect(() => {
    setForm({
      handle: user.handle || '',
      display_name: user.display_name || '',
      bio: user.bio || '',
      avatar_url: user.avatar_url || '',
      cover_url: user.cover_url || '',
      location: user.location || '',
      website: user.website || '',
      origin_country: user.origin_country || '',
    });
  }, [user]);

  const handleSave = async () => {
    setSaving(true);
    setResult(null);
    try {
      await api.adminUpdateProfile(user.id, form);
      setResult({ ok: true, msg: 'Profile saved' });
      setEditing(false);
      onSaved();
    } catch (e: any) {
      setResult({ ok: false, msg: e.message });
    }
    setSaving(false);
  };

  const fields: { key: keyof typeof form; label: string; type?: string }[] = [
    { key: 'handle', label: 'Handle' },
    { key: 'display_name', label: 'Display Name' },
    { key: 'bio', label: 'Bio', type: 'textarea' },
    { key: 'avatar_url', label: 'Avatar URL' },
    { key: 'cover_url', label: 'Cover URL' },
    { key: 'location', label: 'Location' },
    { key: 'website', label: 'Website' },
    { key: 'origin_country', label: 'Country' },
  ];

  return (
    <div className="card p-5">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-semibold text-gray-700 flex items-center gap-2">
          <Pencil className="w-4 h-4" /> Edit Profile
        </h3>
        {!editing ? (
          <button onClick={() => setEditing(true)} className="btn-secondary text-xs py-1 px-3">Edit</button>
        ) : (
          <div className="flex gap-2">
            <button onClick={() => { setEditing(false); setResult(null); }} className="btn-secondary text-xs py-1 px-3 flex items-center gap-1">
              <X className="w-3 h-3" /> Cancel
            </button>
            <button onClick={handleSave} disabled={saving} className="btn-primary text-xs py-1 px-3 flex items-center gap-1">
              <Save className="w-3 h-3" /> {saving ? 'Saving...' : 'Save'}
            </button>
          </div>
        )}
      </div>

      {result && (
        <p className={`text-xs mb-3 ${result.ok ? 'text-green-600' : 'text-red-600'}`}>{result.msg}</p>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {fields.map((f) => (
          <div key={f.key} className={f.type === 'textarea' ? 'md:col-span-2' : ''}>
            <label className="block text-xs font-medium text-gray-500 mb-1">{f.label}</label>
            {editing ? (
              f.type === 'textarea' ? (
                <textarea
                  value={form[f.key]}
                  onChange={(e) => setForm({ ...form, [f.key]: e.target.value })}
                  rows={3}
                  className="w-full px-2 py-1.5 border border-warm-300 rounded text-sm"
                />
              ) : (
                <input
                  type="text"
                  value={form[f.key]}
                  onChange={(e) => setForm({ ...form, [f.key]: e.target.value })}
                  className="w-full px-2 py-1.5 border border-warm-300 rounded text-sm"
                />
              )
            ) : (
              <p className="text-sm text-gray-900 truncate">{String(form[f.key]) || '—'}</p>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Follower/Following Manager ─────────────────────────
function FollowManager({ userId }: { userId: string }) {
  const [tab, setTab] = useState<'followers' | 'following'>('followers');
  const [users, setUsers] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const [addHandle, setAddHandle] = useState('');
  const [actionLoading, setActionLoading] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; msg: string } | null>(null);

  const fetchList = async (relation: 'followers' | 'following') => {
    setLoading(true);
    try {
      const data = await api.adminListFollows(userId, relation);
      setUsers(data.users || []);
    } catch { setUsers([]); }
    setLoading(false);
  };

  useEffect(() => { fetchList(tab); }, [tab, userId]);

  const handleAdd = async () => {
    if (!addHandle.trim()) return;
    setActionLoading(true);
    setResult(null);
    try {
      const relation = tab === 'followers' ? 'follower' : 'following';
      await api.adminManageFollow(userId, 'add', addHandle.trim(), relation);
      setResult({ ok: true, msg: `Added ${addHandle.trim()}` });
      setAddHandle('');
      fetchList(tab);
    } catch (e: any) {
      setResult({ ok: false, msg: e.message });
    }
    setActionLoading(false);
  };

  const handleRemove = async (targetId: string, handle: string) => {
    if (!confirm(`Remove ${handle || targetId}?`)) return;
    setActionLoading(true);
    setResult(null);
    try {
      const relation = tab === 'followers' ? 'follower' : 'following';
      await api.adminManageFollow(userId, 'remove', targetId, relation);
      setResult({ ok: true, msg: `Removed ${handle || targetId}` });
      fetchList(tab);
    } catch (e: any) {
      setResult({ ok: false, msg: e.message });
    }
    setActionLoading(false);
  };

  return (
    <div className="card p-5">
      <h3 className="text-sm font-semibold text-gray-700 flex items-center gap-2 mb-3">
        <Users className="w-4 h-4" /> Followers &amp; Following
      </h3>

      {/* Tabs */}
      <div className="flex gap-1 mb-3">
        <button onClick={() => setTab('followers')}
          className={`px-3 py-1.5 text-xs font-medium rounded-lg transition-colors ${tab === 'followers' ? 'bg-brand-500 text-white' : 'bg-warm-100 text-gray-600 hover:bg-warm-200'}`}>
          Followers
        </button>
        <button onClick={() => setTab('following')}
          className={`px-3 py-1.5 text-xs font-medium rounded-lg transition-colors ${tab === 'following' ? 'bg-brand-500 text-white' : 'bg-warm-100 text-gray-600 hover:bg-warm-200'}`}>
          Following
        </button>
      </div>

      {/* Add */}
      <div className="flex items-center gap-2 mb-3">
        <input type="text" placeholder="Username or user ID" value={addHandle}
          onChange={(e) => setAddHandle(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
          className="flex-1 px-2 py-1.5 border border-warm-300 rounded text-sm" />
        <button onClick={handleAdd} disabled={actionLoading || !addHandle.trim()}
          className="btn-primary text-xs py-1.5 px-3 flex items-center gap-1 disabled:opacity-50">
          <UserPlus className="w-3.5 h-3.5" /> Add
        </button>
      </div>

      {result && (
        <p className={`text-xs mb-2 ${result.ok ? 'text-green-600' : 'text-red-600'}`}>{result.msg}</p>
      )}

      {/* List */}
      <div className="max-h-60 overflow-y-auto border border-warm-200 rounded-lg">
        {loading ? (
          <p className="p-3 text-xs text-gray-500">Loading...</p>
        ) : users.length === 0 ? (
          <p className="p-3 text-xs text-gray-500">No {tab}</p>
        ) : (
          users.map((u) => (
            <div key={u.id} className="flex items-center justify-between px-3 py-2 border-b border-warm-100 last:border-0">
              <div className="flex items-center gap-2 min-w-0">
                <div className="w-7 h-7 bg-brand-100 rounded-full flex items-center justify-center text-brand-600 text-xs font-bold flex-shrink-0">
                  {(u.handle || u.display_name || '?')[0].toUpperCase()}
                </div>
                <div className="min-w-0">
                  <p className="text-sm font-medium text-gray-900 truncate">{u.display_name || u.handle || '—'}</p>
                  <p className="text-[10px] text-gray-500">@{u.handle || '—'}{u.is_official ? ' · Official' : ''}</p>
                </div>
              </div>
              <button onClick={() => handleRemove(u.id, u.handle)} disabled={actionLoading}
                className="text-red-500 hover:text-red-700 p-1 rounded hover:bg-red-50 disabled:opacity-50 flex-shrink-0">
                <UserMinus className="w-3.5 h-3.5" />
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
