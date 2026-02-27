// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0
// See LICENSE file for details

'use client';

import AdminShell from '@/components/AdminShell';
import AdminOnlyGuard from '@/components/AdminOnlyGuard';
import { api } from '@/lib/api';
import { formatDate } from '@/lib/utils';
import { useEffect, useState } from 'react';
import { Search, Trash2, Users, RotateCcw, Pencil, Save, X, Shield, ShieldOff } from 'lucide-react';

export default function GroupsPage() {
  const [groups, setGroups] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [privacy, setPrivacy] = useState('');
  const [sort, setSort] = useState('newest');
  const [offset, setOffset] = useState(0);
  const [selectedGroup, setSelectedGroup] = useState<any | null>(null);
  const [members, setMembers] = useState<any[]>([]);
  const [membersLoading, setMembersLoading] = useState(false);
  const [editGroup, setEditGroup] = useState<any | null>(null);
  const [editForm, setEditForm] = useState({ name: '', description: '', is_private: false, is_active: true });
  const [editSaving, setEditSaving] = useState(false);
  const limit = 50;

  const fetchGroups = () => {
    setLoading(true);
    api.listGroups({ search: search || undefined, limit, offset, privacy: privacy || undefined, sort: sort || undefined })
      .then((data) => setGroups(data.groups ?? []))
      .catch(() => {})
      .finally(() => setLoading(false));
  };

  useEffect(() => { fetchGroups(); }, [offset]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setOffset(0);
    fetchGroups();
  };

  const openGroup = async (group: any) => {
    setSelectedGroup(group);
    setMembersLoading(true);
    try {
      const data = await api.listGroupMembers(group.id);
      setMembers(data.members ?? []);
    } catch {
      setMembers([]);
    } finally {
      setMembersLoading(false);
    }
  };

  const deactivateGroup = async (id: string) => {
    if (!confirm('Deactivate this group?')) return;
    try {
      await api.deleteGroup(id);
      setGroups((prev) => prev.filter((g) => g.id !== id));
      if (selectedGroup?.id === id) setSelectedGroup(null);
    } catch (e: any) {
      alert(e.message);
    }
  };

  const openEditGroup = (g: any, e: React.MouseEvent) => {
    e.stopPropagation();
    setEditGroup(g);
    setEditForm({ name: g.name, description: g.description || '', is_private: g.is_private, is_active: g.is_active });
  };

  const saveGroup = async () => {
    if (!editGroup) return;
    setEditSaving(true);
    try {
      await api.updateGroup(editGroup.id, editForm);
      setEditGroup(null);
      fetchGroups();
    } catch (e: any) {
      alert(e.message);
    }
    setEditSaving(false);
  };

  const removeMember = async (groupId: string, userId: string) => {
    if (!confirm('Remove this member? Key rotation will be triggered.')) return;
    try {
      await api.removeGroupMember(groupId, userId);
      setMembers((prev) => prev.filter((m) => m.user_id !== userId));
    } catch (e: any) {
      alert(e.message);
    }
  };

  const toggleAdmin = async (userId: string, currentRole: string) => {
    if (!selectedGroup) return;
    const newRole = currentRole === 'admin' ? 'member' : 'admin';
    try {
      await api.updateGroupMemberRole(selectedGroup.id, userId, newRole);
      setMembers((prev) => prev.map((m) => m.user_id === userId ? { ...m, role: newRole } : m));
    } catch (e: any) {
      alert(e.message);
    }
  };

  return (
    <AdminOnlyGuard>
    <AdminShell>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Groups & Capsules</h1>
          <p className="text-sm text-gray-500 mt-1">Manage community groups and E2EE capsules</p>
        </div>
      </div>

      <form onSubmit={handleSearch} className="mb-4 flex gap-2 flex-wrap items-center">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 w-4 h-4" />
          <input
            className="pl-9 pr-4 py-2 border rounded-lg w-full text-sm"
            placeholder="Search groups..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <select className="input w-auto" title="Filter by privacy" value={privacy} onChange={(e) => { setPrivacy(e.target.value); setOffset(0); }}>
          <option value="">All Privacy</option>
          <option value="public">Public</option>
          <option value="private">Private</option>
        </select>
        <select className="input w-auto" title="Sort groups" value={sort} onChange={(e) => { setSort(e.target.value); setOffset(0); }}>
          <option value="newest">Newest</option>
          <option value="oldest">Oldest</option>
          <option value="most_members">Most Members</option>
          <option value="name_asc">Name A-Z</option>
        </select>
        <button type="submit" className="px-4 py-2 bg-navy-600 text-white rounded-lg text-sm font-medium bg-blue-700 hover:bg-blue-800">
          Search
        </button>
      </form>

      <div className="flex gap-6">
        {/* Groups list */}
        <div className="flex-1 bg-white rounded-xl border overflow-hidden">
          {loading ? (
            <div className="p-8 text-center text-gray-400">Loading…</div>
          ) : groups.length === 0 ? (
            <div className="p-8 text-center text-gray-400">No groups found</div>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b">
                <tr>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Name</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Type</th>
                  <th className="px-4 py-3 text-center font-medium text-gray-600">Members</th>
                  <th className="px-4 py-3 text-center font-medium text-gray-600">Key v</th>
                  <th className="px-4 py-3 text-center font-medium text-gray-600">Rotation</th>
                  <th className="px-4 py-3 text-left font-medium text-gray-600">Created</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {groups.map((g) => (
                  <tr
                    key={g.id}
                    className={`hover:bg-gray-50 cursor-pointer ${selectedGroup?.id === g.id ? 'bg-blue-50' : ''}`}
                    onClick={() => openGroup(g)}
                  >
                    <td className="px-4 py-3 font-medium text-gray-900">{g.name}</td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${g.is_private ? 'bg-purple-100 text-purple-700' : 'bg-green-100 text-green-700'}`}>
                        {g.is_private ? 'Capsule' : 'Public'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-center">{g.member_count}</td>
                    <td className="px-4 py-3 text-center text-gray-500">v{g.key_version}</td>
                    <td className="px-4 py-3 text-center">
                      {g.key_rotation_needed && (
                        <span className="px-2 py-0.5 rounded-full text-xs bg-amber-100 text-amber-700">Pending</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(g.created_at)}</td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex items-center justify-end gap-1">
                        <button
                          onClick={(e) => openEditGroup(g, e)}
                          className="text-brand-500 hover:text-brand-700 p-1"
                          title="Edit group"
                          type="button"
                        >
                          <Pencil className="w-4 h-4" />
                        </button>
                        <button
                          onClick={(e) => { e.stopPropagation(); deactivateGroup(g.id); }}
                          className="text-red-500 hover:text-red-700 p-1"
                          title="Deactivate group"
                          type="button"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <div className="px-4 py-3 border-t flex items-center gap-3">
            <button disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - limit))}
              className="text-sm px-3 py-1.5 rounded border disabled:opacity-40">Prev</button>
            <button disabled={groups.length < limit} onClick={() => setOffset(offset + limit)}
              className="text-sm px-3 py-1.5 rounded border disabled:opacity-40">Next</button>
          </div>
        </div>

        {/* Member panel */}
        {selectedGroup && (
          <div className="w-72 bg-white rounded-xl border overflow-hidden self-start">
            <div className="px-4 py-3 border-b bg-gray-50 flex items-center gap-2">
              <Users className="w-4 h-4 text-gray-500" />
              <span className="font-semibold text-sm text-gray-800">{selectedGroup.name}</span>
            </div>
            {membersLoading ? (
              <div className="p-6 text-center text-gray-400 text-sm">Loading members…</div>
            ) : members.length === 0 ? (
              <div className="p-6 text-center text-gray-400 text-sm">No members</div>
            ) : (
              <ul className="divide-y divide-gray-100 max-h-96 overflow-y-auto">
                {members.map((m) => (
                  <li key={m.user_id} className="px-4 py-2.5 flex items-center justify-between text-sm">
                    <div>
                      <p className="font-medium text-gray-800">{m.username || m.display_name}</p>
                      <p className="text-xs text-gray-400 flex items-center gap-1">
                        <span className={`inline-block px-1.5 py-0.5 rounded text-[10px] font-semibold ${
                          m.role === 'owner' ? 'bg-purple-100 text-purple-700' :
                          m.role === 'admin' ? 'bg-blue-100 text-blue-700' :
                          'bg-gray-100 text-gray-600'
                        }`}>{m.role}</span>
                        <span>@{m.handle || m.username || '?'}</span>
                      </p>
                    </div>
                    {m.role !== 'owner' && (
                      <div className="flex items-center gap-1">
                        <button
                          type="button"
                          onClick={() => toggleAdmin(m.user_id, m.role)}
                          className={`p-1 ${m.role === 'admin' ? 'text-amber-500 hover:text-amber-700' : 'text-blue-500 hover:text-blue-700'}`}
                          title={m.role === 'admin' ? 'Demote to member' : 'Promote to admin'}
                        >
                          {m.role === 'admin' ? <ShieldOff className="w-3.5 h-3.5" /> : <Shield className="w-3.5 h-3.5" />}
                        </button>
                        <button
                          type="button"
                          onClick={() => removeMember(selectedGroup.id, m.user_id)}
                          className="text-red-400 hover:text-red-600 p-1"
                          title="Remove member"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    )}
                  </li>
                ))}
              </ul>
            )}
            {selectedGroup.key_rotation_needed && (
              <div className="px-4 py-3 border-t bg-amber-50">
                <div className="flex items-center gap-2 text-amber-700 text-xs">
                  <RotateCcw className="w-3.5 h-3.5" />
                  Key rotation pending — will auto-complete next time an admin opens this capsule.
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Edit Group Modal */}
      {editGroup && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={() => setEditGroup(null)}>
          <div className="bg-white rounded-xl p-6 w-full max-w-md mx-4 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-lg font-semibold text-gray-900 mb-4">Edit Group</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Name</label>
                <input className="w-full px-3 py-2 border rounded-lg text-sm" title="Group name" value={editForm.name} onChange={(e) => setEditForm({ ...editForm, name: e.target.value })} />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Description</label>
                <textarea className="w-full px-3 py-2 border rounded-lg text-sm" title="Group description" rows={3} value={editForm.description} onChange={(e) => setEditForm({ ...editForm, description: e.target.value })} />
              </div>
              <div className="flex gap-4">
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={editForm.is_private} onChange={(e) => setEditForm({ ...editForm, is_private: e.target.checked })} className="rounded" />
                  Private (Capsule)
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={editForm.is_active} onChange={(e) => setEditForm({ ...editForm, is_active: e.target.checked })} className="rounded" />
                  Active
                </label>
              </div>
            </div>
            <div className="flex gap-2 justify-end mt-5">
              <button type="button" onClick={() => setEditGroup(null)} className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800">Cancel</button>
              <button type="button" onClick={saveGroup} disabled={editSaving} className="btn-primary text-sm flex items-center gap-1">
                <Save className="w-4 h-4" /> {editSaving ? 'Saving...' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}
    </AdminShell>
    </AdminOnlyGuard>
  );
}
